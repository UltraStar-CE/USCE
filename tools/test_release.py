import contextlib, io, os, plistlib, runpy, tempfile, unittest, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent
version_info = runpy.run_path(str(ROOT / 'generate-version.py'))['version_info']
package = runpy.run_path(str(ROOT / 'package-release.py'))['package']

class ReleaseTests(unittest.TestCase):
    def test_generated_plist_preserves_utf8_permission_text(self):
        generate = runpy.run_path(str(ROOT / 'generate-version.py'))['generate']
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'src/base').mkdir(parents=True)
            (root / 'src/macos').mkdir(parents=True)
            (root / 'installer/settings').mkdir(parents=True)
            (root / 'VERSION').write_text('2026.10.0\n', encoding='utf-8')
            template = (ROOT.parent / 'src/macos/Info.plist.in').read_bytes()
            (root / 'src/macos/Info.plist.in').write_bytes(template)
            generate.__globals__['ROOT'] = root
            with contextlib.redirect_stdout(io.StringIO()):
                generate()
            result = plistlib.loads((root / 'src/macos/Info.plist').read_bytes())
            self.assertEqual(result['NSMicrophoneUsageDescription'],
                'Need microphone access for pitch analysis of the singer\u2019s voice.')
            self.assertEqual(result['CFBundleVersion'], '2026.10.0')

    def test_stable_and_development_versions(self):
        sha = 'a' * 40
        self.assertEqual(version_info('2026.10.0', sha, 12)['version'], '2026.10.0-dev.12+g' + 'a' * 12)
        self.assertTrue(version_info('2026.10.0', sha, 12, True)['version'].endswith('.dirty'))
        self.assertEqual(version_info('2026.10.0', sha, 12, release='2026.10.0')['version'], '2026.10.0')
        for args in [('2026.13.0', sha, 1), ('2026.10.0', 'bad', 1)]:
            with self.assertRaises(ValueError): version_info(*args)
        with self.assertRaises(ValueError): version_info('2026.10.0', sha, 1, True, '2026.10.0')
        with self.assertRaises(ValueError): version_info('2026.10.0', sha, 1, release='2026.11.0')

    def test_matching_six_packages_and_portable_archive(self):
        with tempfile.TemporaryDirectory() as temp:
            source, dest = Path(temp) / 'source', Path(temp) / 'out'
            source.mkdir()
            for stem, ext in [('windows-installer','.exe'),('linux','.AppImage'),('linux-deb','.deb'),('mac-ARM','.dmg'),('mac-x86','.dmg')]:
                name = 'USCE-' + stem + '-2026.10.0'
                folder = source / name
                folder.mkdir()
                (folder / (name + ext)).write_bytes(b'package')
            portable = source / 'USCE-windows-portable-2026.10.0'
            portable.mkdir()
            (portable / 'usce.exe').write_bytes(b'game')
            manifest = package(source, dest, '2026.10.0')
            self.assertEqual(len(manifest), 7)
            self.assertEqual(len((dest / 'SHA256SUMS').read_text().splitlines()), 7)
            with zipfile.ZipFile(str(dest / 'USCE-windows-portable-2026.10.0.zip')) as archive:
                self.assertEqual(archive.namelist(), ['usce.exe'])
            os.utime(portable / 'usce.exe', (1700000000, 1700000000))
            retry = Path(temp) / 'retry'
            self.assertEqual(package(source, retry, '2026.10.0'), manifest)
            with self.assertRaises(ValueError): package(source, dest, '2026.10.0')
            with self.assertRaises(ValueError): package(source, Path(temp) / 'wrong', '2026.11.0')
            (portable / 'usce.exe').unlink()
            with self.assertRaises(ValueError): package(source, Path(temp) / 'missing', '2026.10.0')

if __name__ == '__main__': unittest.main()
