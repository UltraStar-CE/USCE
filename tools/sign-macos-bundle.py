#!/usr/bin/env python3
"""Sign nested executables individually, preserving their own entitlements.

Apple recommends signing nested code before the containing app, rather than
applying the app's signing options to every helper with codesign --deep.
https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/
"""
from pathlib import Path
import subprocess
import sys

bundle = Path(sys.argv[1]).resolve()
magics = {bytes.fromhex(value) for value in ['feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca']}
for program in sorted((bundle / 'Contents/MacOS').rglob('*')):
    if not program.is_file() or not program.resolve().is_relative_to(bundle):
        continue
    with program.open('rb') as source:
        if source.read(4) not in magics:
            continue
    signed = subprocess.run(['codesign','-d',str(program)], capture_output=True).returncode == 0
    command = ['codesign','--force','--sign','-']
    if signed:
        command.append('--preserve-metadata=entitlements')
    subprocess.run(command + [str(program)], check=True)
subprocess.run(['codesign','--force','--sign','-',str(bundle)], check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)], check=True)
