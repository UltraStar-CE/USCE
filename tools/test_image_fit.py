"""Check source-aspect fitting without SDL, graphics drivers or game data."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ImageFitTest(unittest.TestCase):
    def test_physical_aspect_and_size_limit(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('FPC not found; set USCE_FPC')
        with tempfile.TemporaryDirectory(prefix='usce-image-fit-') as temporary:
            output = Path(temporary)
            subprocess.run([compiler, '-B', '-Ciro', '-v0',
                            '-Fu' + str(ROOT / 'src/base'), '-FU' + str(output),
                            '-FE' + str(output), str(ROOT / 'tools/tests/image_fit_test.pas')],
                           check=True, cwd=ROOT)
            executable = output / ('image_fit_test.exe' if os.name == 'nt' else 'image_fit_test')
            result = subprocess.run([str(executable)], capture_output=True, text=True, check=True)
            self.assertIn('54 image fitting cases passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
