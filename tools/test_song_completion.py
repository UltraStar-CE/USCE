"""Test loaded-song scoring boundaries, final lyric lines and medley updates.
Requires a configured checkout, FPC and the game shared libraries.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile

from song_test_units import unit_flags

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fpc', default=shutil.which('fpc'))
    parser.add_argument('--library-dir', type=Path, default=ROOT / 'game')
    args = parser.parse_args()
    if not args.fpc:
        parser.error('FPC was not found; pass --fpc')
    with tempfile.TemporaryDirectory(prefix='usce-completion-') as tmp:
        out = Path(tmp)
        command = [args.fpc, '-B', '-Si', '-Ciro', '-gl', '-v0',
                   '-Fi' + str(ROOT / 'src'), '-Fi' + str(ROOT / 'src/base'),
                   '-FU' + str(out), '-FE' + str(out), '-Fl' + str(args.library_dir.resolve())]
        command += unit_flags(ROOT / 'src')
        env = os.environ.copy()
        env['PATH'] = str(args.library_dir.resolve()) + os.pathsep + env.get('PATH', '')
        if os.name != 'nt':
            env['LD_LIBRARY_PATH'] = str(args.library_dir.resolve()) + os.pathsep + env.get('LD_LIBRARY_PATH', '')
        for name in ('song_completion_test', 'song_clipping_test', 'note_lane_visibility_test',
                     'seek_scoring_test'):
            subprocess.run(command + [str(ROOT / 'tools/tests' / (name + '.pas'))], cwd=ROOT / 'src', check=True)
            exe = out / (name + ('.exe' if os.name == 'nt' else ''))
            subprocess.run([str(exe), str(out)], env=env, check=True)

if __name__ == '__main__':
    main()
