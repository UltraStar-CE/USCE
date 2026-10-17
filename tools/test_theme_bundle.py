import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bundle_themes', Path(__file__).with_name('bundle-themes.py'))
themes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(themes)


class ThemeBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source / 'Modern').mkdir()
        (self.source / 'Modern.ini').write_text('[Theme]\nName=Modern\nCreator=Original Creator\n')
        (self.source / 'Inherited.ini').write_text('[Theme]\nName=Inherited\nBaseTheme=Modern\n')
        (self.source / 'Modern' / 'asset with spaces.png').write_bytes(b'asset bytes')
        (self.source / 'README.md').write_text('Creator credits')
        (self.source / '.github').mkdir()
        (self.source / '.github' / 'workflow.yml').write_text('metadata')
        self.git('init', '--quiet')
        self.git('add', '.')
        self.git('-c', 'user.name=USCE Tests', '-c', 'user.email=tests@example.invalid', 'commit', '--quiet', '-m', 'Themes fixture')
        self.pin = {'repository': themes.REPOSITORY, 'sha': self.git('rev-parse', 'HEAD').strip()}

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.source)] + list(args), text=True)

    def test_all_assets_and_inherited_themes_are_reproducible_without_source_changes(self):
        first, second = self.root / 'first', self.root / 'second'
        manifest = themes.bundle(self.source, first, self.pin)
        themes.bundle(self.source, second, self.pin)
        self.assertEqual(manifest['themes'], ['Inherited.ini', 'Modern.ini'])
        self.assertEqual((first / 'Modern' / 'asset with spaces.png').read_bytes(), b'asset bytes')
        self.assertEqual((first / 'README.md').read_text(), 'Creator credits')
        self.assertFalse((first / '.git').exists())
        self.assertFalse((first / '.github').exists())
        self.assertEqual((first / 'BUNDLE-SOURCE.json').read_bytes(), (second / 'BUNDLE-SOURCE.json').read_bytes())
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_wrong_or_modified_source_and_existing_destination_are_rejected(self):
        destination = self.root / 'bundle'
        with self.assertRaisesRegex(ValueError, 'reviewed commit'):
            themes.bundle(self.source, destination, {**self.pin, 'sha': 'f' * 40})
        (self.source / 'Modern.ini').write_text('modified')
        with self.assertRaisesRegex(ValueError, 'committed contents'):
            themes.bundle(self.source, destination, self.pin)
        self.git('checkout', '--', 'Modern.ini')
        destination.mkdir()
        (destination / 'keep.txt').write_text('keep')
        with self.assertRaisesRegex(ValueError, 'empty'):
            themes.bundle(self.source, destination, self.pin)
        self.assertEqual((destination / 'keep.txt').read_text(), 'keep')

    def test_portable_package_uses_the_complete_bundle_instead_of_old_game_themes(self):
        bundle = self.root / 'bundle'
        themes.bundle(self.source, bundle, self.pin)
        game = self.root / 'game'
        (game / 'themes').mkdir(parents=True)
        (game / 'themes' / 'Stale.ini').write_text('old theme')
        (game / 'usce.exe').write_bytes(b'executable')
        package = self.root / 'portable'
        themes.portable(game, bundle, package, self.pin)
        self.assertTrue((package / 'themes' / 'Inherited.ini').is_file())
        self.assertFalse((package / 'themes' / 'Stale.ini').exists())
        self.assertTrue((game / 'themes' / 'Stale.ini').is_file())
        self.assertEqual(json.loads((package / 'themes' / 'BUNDLE-SOURCE.json').read_text())['sha'], self.pin['sha'])
        with self.assertRaisesRegex(ValueError, 'reviewed commit'):
            themes.portable(game, bundle, self.root / 'wrong', {**self.pin, 'sha': 'f' * 40})

    def test_sparse_checkout_cannot_silently_omit_theme_assets(self):
        self.git('update-index', '--skip-worktree', '--', 'Modern/asset with spaces.png')
        (self.source / 'Modern' / 'asset with spaces.png').unlink()
        self.assertEqual(self.git('status', '--porcelain'), '')
        with self.assertRaisesRegex(ValueError, 'complete checkout'):
            themes.bundle(self.source, self.root / 'bundle', self.pin)
