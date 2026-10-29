"""Compile and run the instrumental-gap timing regression (FPC required)."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import os
ROOT = Path(__file__).resolve().parents[1]
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fpc', default=shutil.which('fpc'))
    args = parser.parse_args()
    if not args.fpc:
        parser.error('FPC was not found; pass --fpc')
    with tempfile.TemporaryDirectory(prefix='usce-gap-') as tmp:
        command = [args.fpc, '-B', '-Ciro', '-gl', '-v0', '-Fu'+str(ROOT/'src/base'), '-FU'+tmp, '-FE'+tmp]
        if os.name == 'nt':
            command += ['-Px86_64', '-WC']
        subprocess.run(command+[str(ROOT/'tools/tests/gap_countdown_test.pas')], check=True)
        subprocess.run([str(Path(tmp)/('gap_countdown_test.exe' if os.name == 'nt' else 'gap_countdown_test'))], check=True)

if __name__ == '__main__':
    main()
