"""Exercise production focus timing, including reversal and SDL tick wrap."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FocusTransitionTests(unittest.TestCase):
    def test_elapsed_time_reversal_defaults_and_tick_wrap(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        source = (Path(__file__).resolve().parents[1] / 'src/menu/UMenuButton.pas').read_text()
        method = source.split('procedure TButton.UpdateFocus;', 1)[1].split('procedure TButton.DrawFocus;', 1)[0]
        harness = '''program FocusTiming;
{$mode delphi}
uses Math, SysUtils;
type TButton = class
  FocusLastTick: cardinal;
  FocusDuration: integer;
  FocusProgress: single;
  SelectBool: boolean;
  procedure UpdateFocus;
end;
var Clock: cardinal;
function SDL_GetTicks: cardinal; begin Result := Clock; end;
procedure TButton.UpdateFocus;
''' + method + '''
procedure Check(Actual, Expected: single);
begin if Abs(Actual-Expected)>0.0001 then raise Exception.Create('focus timing mismatch'); end;
var B: TButton;
begin
  B := TButton.Create;
  B.SelectBool := true; B.FocusDuration := 200;
  Clock := 50; B.UpdateFocus; Check(B.FocusProgress, 0.25);
  Clock := 100; B.UpdateFocus; Check(B.FocusProgress, 0.5);
  B.SelectBool := false;
  Clock := 125; B.UpdateFocus; Check(B.FocusProgress, 0.375);
  Clock := 400; B.UpdateFocus; Check(B.FocusProgress, 0);
  B.SelectBool := true;
  Clock := 1400; B.UpdateFocus; Check(B.FocusProgress, 1);
  B.FocusDuration := 0; B.SelectBool := false; B.UpdateFocus; Check(B.FocusProgress, 0);
  B.SelectBool := true; B.UpdateFocus; Check(B.FocusProgress, 1);
  B.FocusDuration := 100; B.FocusProgress := 0;
  B.FocusLastTick := High(cardinal)-9; Clock := 5;
  B.UpdateFocus; Check(B.FocusProgress, 0.15);
  B.Free;
  WriteLn('PASS: focus timing, reversal, immediate defaults and SDL tick wrap');
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'focus_timing.pas'
            path.write_bytes(harness.encode())
            result = subprocess.run([compiler, '-Mdelphi', '-Ciro', str(path)], cwd=directory,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))], check=True)
