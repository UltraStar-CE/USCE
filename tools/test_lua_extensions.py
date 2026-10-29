#!/usr/bin/env python3
"""Compile and run the native Lua API regression harness against a configured tree."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fpc', default='fpc')
    parser.add_argument('--dll-dir')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    fixture = repo / 'tools/tests/lua-extensions'
    with tempfile.TemporaryDirectory(prefix='usce-lua-') as temp:
        command = [args.fpc, '-Px86_64', '-B', '-Si', '-Ciro', '-gl', '-v0',
                   '-Fi' + str(repo / 'src'), '-Fi' + str(repo / 'src/base'),
                   '-FU' + temp, '-FE' + temp]
        if os.name == 'nt':
            command += ['-WC']
        if args.dll_dir:
            command += ['-Fl' + args.dll_dir]
        dirs = sorted({p.parent for p in (repo / 'src').rglob('*.pas')
                       if 'ctypes' not in p.parts and
                       not any(x.startswith('ffmpeg-') and x != 'ffmpeg-8.0' for x in p.parts)})
        command += ['-Fu' + str(p) for p in dirs]
        command += [str(fixture / 'extensions.pas')]
        subprocess.run(command, cwd=repo / 'src', check=True)
        env = os.environ.copy()
        if args.dll_dir:
            env['PATH'] = args.dll_dir + os.pathsep + env['PATH']
        exe = Path(temp) / ('extensions.exe' if os.name == 'nt' else 'extensions')
        subprocess.run([str(exe), str(fixture / 'one.usdx'), str(fixture / 'two.usdx')],
                       env=env, check=True)


if __name__ == "__main__":
    main()
