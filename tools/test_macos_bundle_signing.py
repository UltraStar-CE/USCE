#!/usr/bin/env python3
"""Verify nested signing order without requiring macOS codesign."""
from pathlib import Path
import plistlib
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


class BundleSigningTest(unittest.TestCase):
    def test_main_is_signed_through_bundle_after_nested_code(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / 'USCE.app'
            programs = bundle / 'Contents/MacOS'
            programs.mkdir(parents=True)
            (bundle / 'Contents/Info.plist').write_bytes(
                plistlib.dumps({'CFBundleExecutable': 'usce'}))
            for name in ['usce', 'libnative.dylib']:
                (programs / name).write_bytes(bytes.fromhex('cffaedfe'))
            (programs / 'readme').write_text('not executable')
            commands = []

            def codesign(command, **kwargs):
                commands.append(command)
                return subprocess.CompletedProcess(command, 0)

            with patch('sys.argv', ['sign-macos-bundle.py', str(bundle)]), \
                    patch('subprocess.run', side_effect=codesign):
                runpy.run_path(str(Path(__file__).with_name('sign-macos-bundle.py')))
            nested = str(programs / 'libnative.dylib')
            self.assertEqual(commands, [
                ['codesign', '-d', nested],
                ['codesign', '--force', '--sign', '-',
                 '--preserve-metadata=entitlements', nested],
                ['codesign', '--force', '--sign', '-', str(bundle)],
                ['codesign', '--verify', '--deep', '--strict', str(bundle)],
            ])


if __name__ == '__main__':
    unittest.main()
