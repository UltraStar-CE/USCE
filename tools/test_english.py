import tempfile
import unittest
from pathlib import Path

from check_english import audit, without_comments, PASCAL


class EnglishCoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('src/base', 'game/languages', 'game/plugins', 'game/themes'):
            (self.root / folder).mkdir(parents=True)
        self.write('game/languages/English.ini', '[Text]\nSING_PRESENT = Present\n')

    def write(self, path, text):
        (self.root / path).write_text(text, encoding='utf-8')

    def errors(self):
        return audit(self.root)[0]

    def test_comments_do_not_invent_keys_or_hide_literal_calls(self):
        self.write('src/base/Test.pas', """// Language.Translate('SING_LINE_COMMENT');
{Language.Translate('SING_BRACE_COMMENT')}
(* Language.Translate('SING_BLOCK_COMMENT') *)
Label := Language.Translate('SING_PRESENT');
""")
        self.assertEqual(self.errors(), [])
        text = "{comment\ncomment}\n'x''y'"
        clean = without_comments(text, PASCAL)
        self.assertEqual(clean.count('\n'), text.count('\n'))
        self.assertIn("'x''y'", clean)

    def test_direct_new_prefix_and_indirect_popup_keys_are_reported(self):
        self.write('src/base/Test.pas', "Language.Translate('NEW_LABEL');\nShowPopup('SING_MISSING');")
        errors = '\n'.join(self.errors())
        self.assertIn('NEW_LABEL:', errors)
        self.assertIn('SING_MISSING:', errors)
        self.assertIn('Test.pas:2', errors)

    def test_player_labels_follow_the_declared_limit(self):
        self.write('src/base/UIni.pas', "IMaxPlayerCount = 24;\nLanguage.Translate('OPTION_PLAYER_' + IntToStr(I));")
        self.write('game/languages/English.ini', '[Text]\n' + ''.join(
            f'OPTION_PLAYER_{i}=Player {i}\n' for i in range(1, 7)))
        errors = self.errors()
        self.assertEqual(len(errors), 18)
        self.assertTrue(any(error.startswith('OPTION_PLAYER_24:') for error in errors))

    def test_unknown_player_limit_fails(self):
        self.write('src/base/UIni.pas', "Language.Translate('OPTION_PLAYER_' + IntToStr(I));")
        self.assertIn('Cannot determine IMaxPlayerCount', '\n'.join(self.errors()))

    def test_registered_runtime_constant_is_not_a_missing_translation(self):
        self.write('src/base/Test.pas', "Language.AddConst('US_VERSION', Version); Language.Translate('US_VERSION');")
        self.write('game/themes/Test.ini', '[Footer]\nText = US_VERSION\n')
        self.assertEqual(self.errors(), [])

    def test_theme_placeholders_are_exempt_only_in_their_runtime_slots(self):
        self.write('game/themes/Test.ini', '[PartyRoundsSelectRound1]\nText = PARTY_SELECTMODE1\n'
                   '[Unrelated]\nText = PARTY_SELECTMODE2\n[Other]\nText = PLAIN\n')
        errors = self.errors()
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith('PARTY_SELECTMODE2:'))

    def test_bundled_party_mode_requires_name_and_description(self):
        self.write('game/plugins/test.usdx', "-- Mode.Name = 'ignored'\nMode.Name = 'Duel'\n")
        errors = self.errors()
        self.assertEqual(len(errors), 2)
        self.assertIn('MODE_DUEL_NAME:', '\n'.join(errors))
        self.assertIn('MODE_DUEL_DESC:', '\n'.join(errors))

    def test_retired_theme_sections_do_not_hide_live_translation_references(self):
        self.write('game/themes/Test.ini', '[EditConvertText1]\nText = SING_EDIT_CONVERT\n'
                   '[EditOpenText1]\nText = SING_EDIT_OPEN\n'
                   '[EditSubTitle]\nText = SING_FULL_EDITOR\n')
        self.write('src/base/Test.pas', "Language.Translate('SING_EDIT_CONVERT');")
        errors = '\n'.join(self.errors())
        self.assertIn('SING_EDIT_CONVERT:', errors)
        self.assertIn('SING_FULL_EDITOR:', errors)
        self.assertNotIn('SING_EDIT_OPEN:', errors)

    def test_empty_and_duplicate_english_entries_fail(self):
        self.write('src/base/Test.pas', "Language.Translate('SING_PRESENT');")
        self.write('game/languages/English.ini', '[Text]\nSING_PRESENT=First\nSING_PRESENT=\n')
        errors = '\n'.join(self.errors())
        self.assertIn('duplicate English key', errors)
        self.assertIn('missing or empty English text', errors)

    def test_extra_theme_package_is_checked_and_missing_directory_fails(self):
        package = self.root / 'package'
        package.mkdir()
        (package / 'Extra.ini').write_text('[Menu]\nText = SING_EXTERNAL\n', encoding='utf-8')
        self.assertIn('SING_EXTERNAL:', '\n'.join(audit(self.root, [package])[0]))
        self.assertIn('does not exist', '\n'.join(audit(self.root, [package / 'missing'])[0]))


    def test_installed_fallback_is_checked_instead_of_repository_copy(self):
        self.write('src/base/UIni.pas', "Language.Translate('OPTION_VALUE_SEPARATE');")
        self.write('game/languages/English.ini', '[Text]\nOPTION_VALUE_SEPARATE=Separate\n')
        installed = self.root / 'installed-English.ini'
        installed.write_text('[Text]\nSING_PRESENT=Present\n', encoding='utf-8')
        self.assertEqual(self.errors(), [])
        errors = audit(self.root, english_path=installed)[0]
        self.assertTrue(any(error.startswith('OPTION_VALUE_SEPARATE:') for error in errors))
        installed.write_text('[Text]\nOPTION_VALUE_SEPARATE=Separate\n', encoding='utf-8')
        self.assertEqual(audit(self.root, english_path=installed)[0], [])

    def test_installed_fallback_cannot_hide_a_missing_indirect_key_family(self):
        self.write('src/base/Test.pas', "Options := ('OPTION_VALUE_SEPARATE');")
        self.write('game/languages/English.ini', '[Text]\nOPTION_VALUE_SEPARATE=Separate\n')
        installed = self.root / 'installed-English.ini'
        installed.write_text('[Text]\nSING_PRESENT=Present\n', encoding='utf-8')
        self.assertTrue(any(error.startswith('OPTION_VALUE_SEPARATE:')
                            for error in audit(self.root, english_path=installed)[0]))

    def test_installed_key_in_wrong_section_is_missing(self):
        self.write('src/base/Test.pas', "Language.Translate('SING_PRESENT');")
        installed = self.root / 'installed-English.ini'
        installed.write_text('[Text]\nOTHER=Other\n[Help]\nSING_PRESENT=Present\n', encoding='utf-8')
        self.assertTrue(any(error.startswith('SING_PRESENT:')
                            for error in audit(self.root, english_path=installed)[0]))

    def test_missing_installed_english_file_fails_cleanly(self):
        errors = audit(self.root, english_path=self.root / 'missing.ini')[0]
        self.assertIn('cannot read English fallback', '\n'.join(errors))


if __name__ == '__main__':
    unittest.main()
