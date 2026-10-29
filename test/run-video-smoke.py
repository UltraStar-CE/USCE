#!/usr/bin/env python3
"""Build and run the actual USCE renderer/video units in an isolated test program."""

import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


def make_fixture(destination):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg is needed to generate the video test fixture")
    colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)]
    # A standard video size also works on hardware decoders that reject tiny
    # synthetic frames. Reuse four frames instead of storing the entire clip.
    frames = []
    for phase in range(4):
        rows = []
        for quadrant in (0, 2):
            rows.append(bytes(colors[(quadrant + phase) % 4]) * 640 +
                        bytes(colors[(quadrant + phase + 1) % 4]) * 640)
        frames.append(rows[0] * 360 + rows[1] * 360)
    command = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "1280x720",
        "-framerate", "25", "-i", "pipe:0",
        "-vf", "scale=out_color_matrix=bt709:out_range=tv",
        "-c:v", "libx264", "-crf", "10", "-g", "25", "-pix_fmt", "yuv420p",
        "-colorspace", "bt709", "-color_range", "tv",
        "-color_trc", "bt709", "-color_primaries", "bt709", str(destination)
    ]
    with subprocess.Popen(command, stdin=subprocess.PIPE) as encoder:
        for frame in range(100):
            encoder.stdin.write(frames[frame // 25])
        encoder.stdin.close()
        if encoder.wait() != 0:
            raise RuntimeError("Could not encode the video test fixture")
    destination.with_suffix(destination.suffix + ".corrupt").write_bytes(b"invalid video\n")
    # A video stream that loads and ends without a decodable frame: dropping
    # the only IDR slice leaves P frames that reference a missing picture.
    frame = bytes(colors[0]) * (640 * 180) + bytes(colors[2]) * (640 * 180)
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "640x360",
        "-framerate", "25", "-i", "pipe:0",
        "-c:v", "libx264", "-g", "250", "-bf", "0", "-x264-params", "scenecut=0",
        "-pix_fmt", "yuv420p", "-bsf:v", "filter_units=remove_types=5",
        "-f", "mp4", str(destination.with_suffix(destination.suffix + ".noframe"))
    ], input=frame * 10, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderers", nargs="+", default=["gl"],
                        choices=["gl", "gl2", "gles2", "gles3"])
    parser.add_argument("--skip-video", action="store_true")
    parser.add_argument("--keep-temp", action="store_true")
    parser.add_argument("--build-only", "--compile-only", action="store_true")
    parser.add_argument("--output-dir", "--output-directory", type=Path)
    parser.add_argument("--hwdec", choices=["no", "auto", "auto-copy"], default="no")
    parser.add_argument("--require-hardware", action="store_true")
    args = parser.parse_args()
    if args.require_hardware and (args.hwdec == "no" or args.skip_video):
        parser.error("--require-hardware needs --hwdec auto or auto-copy and video tests")
    root = Path(__file__).resolve().parent.parent
    src = root / "src"
    if not (src / "Makefile").exists() or not (src / "paths.inc").exists():
        parser.error("configure and build USCE before running this test")
    makefile = (src / "Makefile").read_text()
    suffix = re.search(r"(?m)^EXEEXT[ \t]*\?=[ \t]*(.*)$", makefile).group(1).strip()
    windows = suffix == ".exe"

    def compiler_path(path):
        # The MSYS Python interpreter returns POSIX paths; native FPC needs
        # drive paths inside Pascal source as well as in compiler arguments.
        if windows:
            if os.name != "nt":
                return subprocess.check_output(["cygpath", "-w", str(path)], text=True).strip()
            # MSYS rewrites prefixed forward-slash drive paths such as
            # -FUD:/a/build. Backslashes inside quoted arguments avoid that.
            return str(path).replace("/", "\\")
        return path.as_posix()

    if args.output_dir:
        temp = args.output_dir.resolve()
        temp.mkdir(parents=True, exist_ok=True)
    else:
        temp = Path(tempfile.mkdtemp(prefix="usdx-video-smoke-"))
    success = False
    try:
        # FPC can reuse PPUs beside the program source even with -B. Keep every
        # compiler search/output directory fresh when --output-dir is reused.
        compile_dir = Path(tempfile.mkdtemp(prefix="compile-", dir=temp))
        # USCE's main program explicitly orders cyclic Pascal units and selects
        # versioned bindings. Reuse that list instead of maintaining a second one.
        project = (src / "usce.dpr").read_text()
        marker = re.search(r"(?m)^const\s*\n\s*sLineBreakWin", project)
        if not marker:
            raise RuntimeError("Could not locate the end of the application's unit list")
        header = project[:marker.start()].replace("program usce;", "program VideoSmoke;")
        # The test has no app icon/resources and must retain a console on Windows.
        header = re.sub(r"(?m)^\s*\{\$R [^\n]+\}\s*$", "", header)
        header = header.replace("program VideoSmoke;", "program VideoSmoke;\n{$DEFINE CONSOLE}")
        source_prefix = compiler_path(src)
        header = re.sub(
            r"in '([^']+)'",
            lambda match: "in '" + source_prefix + "/" + match[1].replace("\\", "/") + "'",
            header,
        )
        source = compile_dir / "VideoSmoke.pas"
        source.write_text(header + (root / "test" / "VideoSmoke.inc").read_text())
        executable = temp / ("VideoSmoke" + suffix)
        compiled_executable = compile_dir / executable.name
        extra_flags = [
            "-B", "-dCONSOLE", "-Fi" + source_prefix, "-FU" + compiler_path(compile_dir),
            "-FE" + compiler_path(compile_dir), "-o" + compiler_path(compiled_executable)
        ]
        if windows:
            extra_flags.append("-WC")
        extra_flags.append(compiler_path(source))
        extra = " ".join(shlex.quote(value) for value in extra_flags)
        # Use the configured compiler, defines and link flags. The final -FU/-FE
        # keep all generated units and binaries outside the working tree.
        recipe = "video-smoke-build:; $(PPC) $(PFLAGS_ALL) " + extra
        subprocess.run([
            "make", "--no-print-directory", "-s", "-C", str(src),
            "PCUNIT_FLAGS=",
            "--eval=.PHONY: video-smoke-build", "--eval=" + recipe, "video-smoke-build"
        ], check=True)
        shutil.copy2(compiled_executable, executable)
        if args.build_only:
            print("Built", executable, flush=True)
            success = True
            return
        fixture = temp / "quadrants.mp4"
        if not args.skip_video:
            make_fixture(fixture)
        for renderer in args.renderers:
            environment = dict(os.environ)
            if renderer == "gl2":
                environment["MESA_GL_VERSION_OVERRIDE"] = "2.1"
            elif renderer == "gles2":
                environment["MESA_GLES_VERSION_OVERRIDE"] = "2.0"
            elif renderer == "gles3":
                environment["MESA_GLES_VERSION_OVERRIDE"] = "3.0"
            command = [str(executable), renderer]
            if not args.skip_video:
                command.extend([str(fixture), args.hwdec])
            print("Running", renderer, flush=True)
            # ConsoleWriteLn checks for a console window on Windows, including
            # when output is redirected. Keep that console hidden during tests.
            process_options = {}
            if windows and os.name == "nt":
                startup = subprocess.STARTUPINFO()
                startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startup.wShowWindow = subprocess.SW_HIDE
                process_options = {"startupinfo": startup,
                                   "creationflags": subprocess.CREATE_NEW_CONSOLE}
            result = subprocess.run(command, cwd=temp, env=environment,
                                    capture_output=True, text=True, timeout=90,
                                    **process_options)
            output = result.stdout + result.stderr
            (temp / (renderer + ".log")).write_text(output)
            print(output, end="", flush=True)
            result.check_returncode()
            if not args.skip_video:
                selection, marker, _ = output.partition("PASS configured video provider selection")
                if not marker or re.search(r"(?:ERROR|CRITICAL):", selection):
                    raise RuntimeError("Configured video provider selection did not complete without errors")
            if output.count("Using libmpv video") < output.count("Testing MPV_Video"):
                raise RuntimeError("The MPV playback test silently fell back to another backend")
            if "Testing expected libmpv initialization failure" in output and \
                    "Using fallback FFmpeg_Video" not in output:
                raise RuntimeError("The forced render-context failure did not use FFmpeg fallback")
            if "Testing libmpv end without a video frame" in output and \
                    "libmpv reached the end without a video frame" not in output:
                raise RuntimeError("libmpv did not reject a stream that ended without a frame")
            if "Testing MPV_Video startup" in output:
                if "Reusing libmpv player" not in output:
                    raise RuntimeError("The libmpv player was not reused across opens")
                if args.hwdec == "no":
                    if "Probing hardware decoding for" in output:
                        raise RuntimeError("Software decoding probed a hardware decoder")
                else:
                    if output.count("Probing hardware decoding for") != 1:
                        raise RuntimeError("The hardware decoder was not probed exactly once per session")
                    if "Using remembered decoder" not in output:
                        raise RuntimeError("The probed decoder was not remembered for the next open")
            if args.require_hardware:
                decoders = re.findall(r"Hardware decoder: ([\w-]+)", output)
                if not decoders or decoders[-1] == "no":
                    raise RuntimeError("Playback did not finish with an active hardware decoder")
        success = True
    finally:
        if success and not (args.keep_temp or args.output_dir or args.build_only):
            shutil.rmtree(temp)
        else:
            print("Test artifacts:", temp, flush=True)


if __name__ == "__main__":
    main()
