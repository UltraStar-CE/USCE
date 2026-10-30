"""Run the actual FFmpeg worker decoder with generated RGB frames and no window.

Requires a configured checkout, FPC, ffmpeg and the game shared libraries.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fpc', default=shutil.which('fpc'))
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--library-dir', type=Path, default=ROOT / 'game')
    args = parser.parse_args()
    if not args.fpc or not args.ffmpeg:
        parser.error('FPC and ffmpeg are required')
    with tempfile.TemporaryDirectory(prefix='usce-background-video-') as tmp:
        out = Path(tmp)
        fixture = out / 'colors.mkv'
        colors = b''.join(bytes(rgb) * (64 * 64 * 25) for rgb in
                          [(255, 0, 0), (0, 255, 0), (0, 0, 255)])
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                        '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '64x64',
                        '-framerate', '25', '-i', 'pipe:0', '-c:v', 'ffv1', '-g', '1',
                        str(fixture)], input=colors, check=True)
        slow_fixture = out / 'slow.mkv'
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                        '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '64x64',
                        '-framerate', '1', '-i', 'pipe:0', '-c:v', 'ffv1', '-g', '1',
                        str(slow_fixture)], input=b''.join(bytes(rgb) * (64 * 64) for rgb in
                        [(255, 0, 0), (0, 255, 0), (0, 0, 255)]), check=True)
        command = [args.fpc, '-B', '-Si', '-Ciro', '-gl', '-v0',
                   '-Fi' + str(ROOT / 'src'), '-Fi' + str(ROOT / 'src/base'),
                   '-FU' + str(out), '-FE' + str(out), '-Fl' + str(args.library_dir.resolve())]
        if os.name == 'nt':
            command += ['-Px86_64', '-WC']
        directories = sorted({p.parent for p in (ROOT / 'src').rglob('*.pas')
            if 'ctypes' not in p.parts and not any(
                part.startswith('ffmpeg-') and part != 'ffmpeg-8.0' for part in p.parts)})
        command += ['-Fu' + str(p) for p in directories]
        command += [str(ROOT / 'tools/tests/background_video_test.pas')]
        subprocess.run(command, cwd=ROOT / 'src', check=True)
        env = os.environ.copy()
        env['PATH'] = str(args.library_dir.resolve()) + os.pathsep + env.get('PATH', '')
        if sys.platform != 'win32':
            env['LD_LIBRARY_PATH'] = str(args.library_dir.resolve()) + os.pathsep + env.get('LD_LIBRARY_PATH', '')
        exe = out / ('background_video_test.exe' if os.name == 'nt' else 'background_video_test')
        subprocess.run([str(exe), str(fixture), str(slow_fixture)], env=env, timeout=25, check=True)


if __name__ == '__main__':
    main()
