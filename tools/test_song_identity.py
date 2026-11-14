#!/usr/bin/env python3
"""Compile and run the native song identity regression harness against a configured tree."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

from song_test_units import unit_flags

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fpc', default='fpc')
    parser.add_argument('--dll-dir')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    fixture = repo / 'tools/tests'
    with tempfile.TemporaryDirectory(prefix='usce-identity-') as temp:
        command = [args.fpc, '-B', '-Si', '-Ciro', '-gl', '-v0',
                   '-Fi' + str(repo / 'src'), '-Fi' + str(repo / 'src/base'),
                   '-FU' + temp, '-FE' + temp]
        if args.dll_dir:
            command += ['-Fl' + args.dll_dir]
        command += unit_flags(repo / 'src')
        command += [str(fixture / 'song_identity_test.pas')]
        subprocess.run(command, cwd=repo / 'src', check=True)
        env = os.environ.copy()
        if args.dll_dir:
            env['PATH'] = args.dll_dir + os.pathsep + env['PATH']
        exe = Path(temp) / ('song_identity_test.exe' if os.name == 'nt' else 'song_identity_test')
        data = Path(temp) / 'charts'
        data.mkdir()
        subprocess.run([str(exe), str(data)], env=env, check=True)

if __name__ == "__main__":
    main()
