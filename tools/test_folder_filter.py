"""Compile the production matcher and exercise portable folder query semantics."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FolderFilterTests(unittest.TestCase):
    def test_relative_paths_boundaries_anchors_unicode_and_folder_choices(self):
        fpc = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not fpc:
            self.skipTest('Free Pascal is not installed')
        source = Path(__file__).resolve().parents[1] / 'src/base'
        harness = r'''program FolderProbe;
{$mode Delphi}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cwstring,{$ENDIF} SysUtils, Classes, UFolderFilter;
procedure Check(OK: boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
var Choices: TStringList;
begin
  Check(NormalizeFolderPath('Denglish\Kids\GanzKlein\') = '/Denglish/Kids/GanzKlein/', 'separators');
  Check(NormalizeFolderPath('./') = '/', 'root directory');
  Check(MatchesFolderPath('/Denglish/Kids/GanzKlein/', 'Kids'), 'unanchored name');
  Check(MatchesFolderPath('/English/Kids/', 'Kids'), 'same name in another root');
  Check(MatchesFolderPath('/Archive/Denglish/Kids/', 'Denglish/Kids'), 'unanchored sequence');
  Check(not MatchesFolderPath('/Archive/Denglish/Kids/', '/Denglish/Kids'), 'anchored sequence');
  Check(MatchesFolderPath('/Denglish/Kids/GanzKlein/', '/Denglish/Kids'), 'descendants');
  Check(not MatchesFolderPath('/DenglishExtra/Kids/', '/Denglish'), 'root boundary');
  Check(not MatchesFolderPath('/Denglish/KidsExtra/', 'Kids'), 'name boundary');
  Check(not MatchesFolderPath('/NotKids/', 'Kids'), 'leading boundary');
  Check(MatchesFolderPath('/Denglish/Adults/', 'Kids, Adults'), 'OR alternatives');
  Check(MatchesFolderPath('/Denglish/Kids/', '/'), 'whole library');
  Check(MatchesFolderPath('/', '/'), 'direct root songs');
  Check(MatchesFolderPath('/Deutsch/Für Kinder/', 'für kinder'), 'Unicode case folding');
  Choices := TStringList.Create;
  try
    AddFolderChoices('/Denglish/Kids/GanzKlein/', 0, Choices);
    Check(Choices.Count = 0, 'off');
    AddFolderChoices('/Denglish/Kids/GanzKlein/', 1, Choices);
    Check((Choices.Count = 1) and (Choices[0] = '/Denglish/'), 'root folders');
    Choices.Clear;
    AddFolderChoices('/Denglish/Kids/GanzKlein/', 2, Choices);
    Check((Choices.Count = 3) and (Choices[2] = '/Denglish/Kids/GanzKlein/'), 'all containing folders');
    AddFolderChoices('/Denglish/Kids/GanzKlein/', 2, Choices);
    Check(Choices.Count = 3, 'shared directory deduplication');
    AddFolderChoices('/', 2, Choices);
    Check(Choices.Count = 4, 'songs directly under SongDir');
  finally Choices.Free; end;
  Writeln('PASS');
end.
'''
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            program = folder / 'folderprobe.pas'
            program.write_text(harness, encoding='utf-8')
            result = subprocess.run([fpc, '-Fu' + str(source), '-FU' + temp,
                                     '-FE' + temp, str(program)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            exe = folder / ('folderprobe.exe' if os.name == 'nt' else 'folderprobe')
            result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()
