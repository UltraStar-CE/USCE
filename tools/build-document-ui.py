#!/usr/bin/env python3
"""Build the optional native document frontend; pass extra CMake flags after --."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-dir', type=Path, default=root / 'build/document-frontend')
args, extra = parser.parse_known_args()
if extra[:1] == ['--']:
    extra = extra[1:]
subprocess.run(['cmake', '-S', str(root / 'src/frontend'), '-B', str(args.build_dir),
                '-DCMAKE_BUILD_TYPE=Release', *extra], check=True)
subprocess.run(['cmake', '--build', str(args.build_dir), '--config', 'Release', '--parallel', '6'], check=True)
suffix = '.dll' if sys.platform == 'win32' else '.dylib' if sys.platform == 'darwin' else '.so'
name = 'usce-document-ui' + suffix
candidates = [args.build_dir / name, args.build_dir / 'Release' / name]
binary = next((p for p in candidates if p.is_file()), None)
if binary is None:
    raise SystemExit('Frontend library not found after build')
shutil.copyfile(binary, root / 'game' / name)
shutil.copytree(args.build_dir / 'document-ui-licenses', root / 'game/document-ui-licenses', dirs_exist_ok=True)
print(root / 'game' / name)
