"""Test persistent local song-problem flags and failed-write rollback.
Requires a configured checkout, FPC and the game shared libraries.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fpc', default=shutil.which('fpc'))
    parser.add_argument('--library-dir', type=Path, default=ROOT / 'game')
    args = parser.parse_args()
    if not args.fpc:
        parser.error('FPC was not found; pass --fpc')
    platform = 'win' if os.name == 'nt' else 'darwin' if sys.platform == 'darwin' else 'freebsd' if sys.platform.startswith('freebsd') else 'linux'
    if not (ROOT / 'src' / ('config-' + platform + '.inc')).exists():
        parser.error('Run autogen.sh and configure first')
    with tempfile.TemporaryDirectory(prefix='usce-completion-') as tmp:
        out = Path(tmp)
        command = [args.fpc, '-B', '-Si', '-Ciro', '-gl', '-v0',
                   '-Fi' + str(ROOT / 'src'), '-Fi' + str(ROOT / 'src/base'),
                   '-FU' + str(out), '-FE' + str(out), '-Fl' + str(args.library_dir.resolve())]
        if os.name == 'nt':
            command += ['-Px86_64', '-WC']
        directories = sorted({p.parent for p in (ROOT / 'src').rglob('*.pas')
            if 'ctypes' not in p.parts and not any(
                part.startswith('ffmpeg-') and part != 'ffmpeg-8.0' for part in p.parts)})
        command += ['-Fu' + str(p) for p in directories]
        env = os.environ.copy()
        env['XDG_CONFIG_HOME'] = str(out)
        env['HOME'] = str(out)
        env['PATH'] = str(args.library_dir.resolve()) + os.pathsep + env.get('PATH', '')
        if os.name != 'nt':
            env['LD_LIBRARY_PATH'] = str(args.library_dir.resolve()) + os.pathsep + env.get('LD_LIBRARY_PATH', '')
        for name in ('song_problems_test', 'song_problem_filter_test'):
            subprocess.run(command + [str(ROOT / 'tools/tests' / (name + '.pas'))], cwd=ROOT / 'src', check=True)
            exe = out / (name + ('.exe' if os.name == 'nt' else ''))
            subprocess.run([str(exe), str(out)], env=env, check=True)

if __name__ == '__main__':
    main()
