#!/usr/bin/env python3
# Regression checks for the video backends. After configuring and building
# USCE, run the video clock and real-renderer tests from the repository root:
#
#   mkdir -p build/video-tests
#   fpc -Fusrc/media -FUbuild/video-tests -FEbuild/video-tests test/VideoSyncTest.pas
#   build/video-tests/VideoSyncTest
#   python3 test/run-video-smoke.py --renderers gl gl2 gles2 gles3
#
# The playback test generates its fixtures and builds a separate executable;
# tests are not installed with the game. It needs Python 3, FFmpeg with libx264
# and a display (use `xvfb-run -a` on headless Linux). CI checks builds with and
# without MPV. On a physical GPU, add `--hwdec auto --require-hardware` to
# verify hardware decoding. Longer playback and microphone responsiveness still
# require native testing.
"""Build and run the actual USCE renderer/video units in an isolated test program."""

import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile

# Three times the slowest measured run of one renderer (57 s, Windows with MPV).
RUN_TIMEOUT = 180


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
    make_failure_fixture(ffmpeg, destination.with_suffix(destination.suffix + ".oversize"))


def make_failure_fixture(ffmpeg, path):
    """Write MPEG-TS: 1.5 seconds at SAR 1:1, then 1.5 seconds at SAR 256:1.

    Both segments decode 320x256 quadrants. The second one's display width is
    81920, beyond GPU texture limits, so the renderer cannot allocate its
    texture after playback has started. Concatenating the segments keeps the
    SPS change that a remuxer would normalize away.
    """
    pattern = ("color=c=red:size=320x256:rate=24,"
               "drawbox=x=160:y=0:w=160:h=128:color=0x00ff00:t=fill,"
               "drawbox=x=0:y=128:w=160:h=128:color=blue:t=fill,"
               "drawbox=x=160:y=128:w=160:h=128:color=yellow:t=fill")
    with tempfile.TemporaryDirectory(prefix="video-sar-", dir=path.parent) as temporary:
        segments = []
        for index, sar in enumerate(("1/1", "256/1")):
            segment = Path(temporary) / f"segment-{index}.ts"
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", pattern, "-t", "1.5",
                "-vf", f"setsar={sar}:max=65535", "-an",
                "-c:v", "libx264", "-threads", "1", "-preset", "ultrafast",
                "-g", "12", "-bf", "0", "-pix_fmt", "yuv420p",
                "-muxdelay", "0", "-muxpreload", "0",
                "-output_ts_offset", str(index * 1.5), str(segment),
            ], check=True, timeout=30)
            segments.append(segment.read_bytes())
        path.write_bytes(b"".join(segments))


def passed_section(output, start, end):
    """The log between a test's start line and its PASS line, or None without both."""
    _, started, rest = output.partition(start)
    body, passed, _ = rest.partition(end)
    return body if started and passed else None


def has_errors(text):
    return re.search(r"(?:ERROR|CRITICAL):", text) is not None


def open_times(output):
    """Open times in ms by label, each label checked against the backend's log.

    The backend logs "Reusing libmpv player" when an open adopts the parked
    player. A time labelled reused without that line, or labelled fresh with
    it, would report something else than its name says.
    """
    section = passed_section(output, "Measuring video open times", "PASS open times measured")
    if section is None:
        raise RuntimeError("The open-time measurement did not complete")
    times = {"fresh": [], "reused": []}
    adopted = False
    for line in section.splitlines():
        if "Reusing libmpv player" in line:
            adopted = True
        match = re.match(r"OPEN-TIME (fresh|reused) (\d+)$", line)
        if match:
            if adopted != (match[1] == "reused"):
                raise RuntimeError("An open time is labelled %s but the player was %s" % (
                    match[1], "reused" if adopted else "new"))
            times[match[1]].append(int(match[2]))
            adopted = False
    if len(times["fresh"]) != 3 or len(times["reused"]) != 6:
        raise RuntimeError("Expected three fresh and six reused open times, got %r" % times)
    return times


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderers", nargs="+", default=["gl"],
                        choices=["gl", "gl2", "gles2", "gles3"])
    parser.add_argument("--skip-video", action="store_true")
    parser.add_argument("--prebuilt", type=Path,
                        help="run this existing test executable without a compiler")
    parser.add_argument("--fixture", type=Path,
                        help="existing quadrants.mp4 and its .corrupt/.noframe/.oversize companions")
    parser.add_argument("--keep-temp", action="store_true")
    parser.add_argument("--build-only", "--compile-only", action="store_true")
    parser.add_argument("--output-dir", "--output-directory", type=Path)
    parser.add_argument("--hwdec", choices=["no", "auto", "auto-copy"], default="no")
    parser.add_argument("--require-hardware", action="store_true")
    parser.add_argument("--expect-missing-mpv", action="store_true",
                        help="test an MPV-enabled executable with no loadable libmpv")
    args = parser.parse_args()
    if args.require_hardware and (args.hwdec == "no" or args.skip_video):
        parser.error("--require-hardware needs --hwdec auto or auto-copy and video tests")
    if args.expect_missing_mpv and (args.skip_video or args.build_only or
                                   args.require_hardware):
        parser.error("--expect-missing-mpv needs video playback without hardware options")
    root = Path(__file__).resolve().parent.parent
    src = root / "src"
    if args.prebuilt:
        if args.build_only:
            parser.error("--prebuilt cannot be combined with --build-only")
        args.prebuilt = args.prebuilt.resolve()
        if not args.prebuilt.is_file():
            parser.error("--prebuilt must name an existing executable")
        if not args.skip_video and not args.fixture:
            parser.error("--prebuilt needs --fixture unless --skip-video is used")
        suffix = args.prebuilt.suffix
    else:
        if not (src / "Makefile").exists() or not (src / "paths.inc").exists():
            parser.error("configure and build USCE before running this test")
        makefile = (src / "Makefile").read_text()
        suffix = re.search(r"(?m)^EXEEXT[ \t]*\?=[ \t]*(.*)$", makefile).group(1).strip()
    windows = suffix.lower() == ".exe"
    if args.fixture:
        args.fixture = args.fixture.resolve()
        for name in (str(args.fixture), str(args.fixture) + ".corrupt",
                     str(args.fixture) + ".noframe", str(args.fixture) + ".oversize"):
            if not Path(name).is_file():
                parser.error("missing fixture: " + name)

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
        if args.prebuilt:
            executable = args.prebuilt
        else:
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
            # Menu-cache tests provide an empty theme path list. Keep cthreads
            # first on Unix by adding Classes beside the other library units.
            header = header.replace("  AnyAscii", "  Classes,\n  AnyAscii", 1)
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
        fixture = args.fixture or temp / "quadrants.mp4"
        if not args.skip_video and not args.fixture:
            make_fixture(fixture)
        measured = []
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
                if args.expect_missing_mpv:
                    command.append("missing-mpv")
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
            # Both streams go straight to files, so a run that is cut off keeps
            # its output. They stay separate: the libraries write to stderr
            # unbuffered, which would land inside the test's buffered lines.
            log = temp / (renderer + ".log")
            errors_log = temp / (renderer + ".stderr.log")
            with log.open("wb") as stream, errors_log.open("wb") as error_stream:
                try:
                    code = subprocess.run(command, cwd=temp, env=environment, stdout=stream,
                                          stderr=error_stream, timeout=RUN_TIMEOUT,
                                          **process_options).returncode
                except subprocess.TimeoutExpired:
                    code = None
            output = log.read_text(errors="replace") + errors_log.read_text(errors="replace")
            print(output, end="", flush=True)
            if code is None:
                raise RuntimeError("%s did not finish within %d s" % (renderer, RUN_TIMEOUT))
            if code != 0:
                raise RuntimeError("%s exited with status %d" % (renderer, code))
            if args.expect_missing_mpv:
                if ("PASS missing libmpv fallback:" not in output or
                        output.count("; FFmpeg plays all videos") != 1 or
                        "Using libmpv video" in output or has_errors(output)):
                    raise RuntimeError("Missing-libmpv fallback did not pass with one warning and no errors")
                continue
            if args.skip_video:
                continue
            with_mpv = "Testing MPV_Video" in output
            # Tests that must pass without logging an error.
            clean = [("Testing configured video provider selection",
                      "PASS configured video provider selection"),
                     ("Testing retained menu video FFmpeg_Video", "PASS retained menu video FFmpeg_Video:")]
            if with_mpv:
                clean += [("Testing retained menu video MPV_Video", "PASS retained menu video MPV_Video:"),
                          ("Testing menu drawing after libmpv", "PASS menu drawing after libmpv:"),
                          ("Testing in-memory preview", "PASS in-memory preview:"),
                          ("Testing two MPV players", "PASS two MPV players:")]
            for start, end in clean:
                section = passed_section(output, start, end)
                if section is None or has_errors(section):
                    raise RuntimeError("'%s' did not pass without errors" % start)
            if not with_mpv:
                continue
            section = passed_section(output, "Testing retained menu video MPV_Video",
                                     "PASS retained menu video MPV_Video:")
            if section.count("Using libmpv video") != 1:
                raise RuntimeError("The retained menu video was opened more than once")
            section = passed_section(output, "Testing real mid-stream render-target failure",
                                     "PASS mid-stream render-target failure:")
            errors = re.findall(r"(?m)^ERROR:.*$", section or "")
            if (section is None or len(errors) != 1 or
                    "Cannot create libmpv video texture" not in errors[0] or "CRITICAL:" in section):
                raise RuntimeError("Mid-stream test did not finish with exactly the expected render-target error")
            if output.count("Using libmpv video") < output.count("Testing MPV_Video"):
                raise RuntimeError("The MPV playback test silently fell back to another backend")
            measured.append((renderer, open_times(output)))
            if "Using fallback FFmpeg_Video" not in output:
                raise RuntimeError("The forced render-context failure did not use FFmpeg fallback")
            if "libmpv reached the end without a video frame" not in output:
                raise RuntimeError("libmpv did not reject a stream that ended without a frame")
            if args.hwdec == "no":
                if "Probing hardware decoding for" in output:
                    raise RuntimeError("Software decoding probed a hardware decoder")
            else:
                if output.count("Probing hardware decoding for") != 1:
                    raise RuntimeError("The hardware decoder was not probed exactly once per session")
                if "Using remembered decoder" not in output:
                    raise RuntimeError("The probed decoder was not remembered for the next open")
            if args.require_hardware:
                # The startup test closes players before their decoder switch.
                # Inspect the playback test, which runs long enough to switch.
                playback = passed_section(output, "Testing MPV_Video\n", "PASS MPV_Video:") or ""
                decoders = re.findall(r"Hardware decoder: ([\w-]+)", playback)
                if not decoders or decoders[-1] == "no":
                    raise RuntimeError("MPV playback did not finish with an active hardware decoder")
        for renderer, times in measured:
            print("Open times in ms, %s: new player %s, reused player %s" % (
                renderer, times["fresh"], times["reused"]))
        success = True
    finally:
        if success and not (args.keep_temp or args.output_dir or args.build_only):
            shutil.rmtree(temp)
        else:
            print("Test artifacts:", temp, flush=True)


if __name__ == "__main__":
    main()
