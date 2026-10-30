"""Exercise the production transition initializer with reentrant callbacks."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FadeTargetTests(unittest.TestCase):
    def run_harness(self, harness):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fade_target.pas'
            path.write_bytes(harness.encode())
            result = subprocess.run([compiler, '-Mdelphi', '-Ciro', str(path)], cwd=directory,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))], check=True)

    def test_once_per_target_and_redirect_from_onshow(self):
        source = (Path(__file__).resolve().parents[1] / 'src/menu/UDisplay.pas').read_text()
        method = source.split('function TDisplay.InitializeNextScreen: boolean;', 1)[1].split('function TDisplay.Draw:', 1)[0]
        harness = '''program FadeTarget;
{$mode delphi}
uses SysUtils;
type
  TMenu = class;
  PMenu = ^TMenu;
  TMenu = class
    Calls: integer;
    Redirect: PMenu;
    procedure OnShow;
  end;
  TDisplay = class
    ShownScreen, NextScreen: PMenu;
    FadeStartTime: cardinal;
    function InitializeNextScreen: boolean;
  end;
var D: TDisplay;
procedure TMenu.OnShow;
begin Inc(Calls); if Redirect <> nil then D.NextScreen := Redirect; end;
function TDisplay.InitializeNextScreen: boolean;
''' + method + '''
procedure Check(Value: boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var A, B, C: TMenu;
begin
  D := TDisplay.Create; A := TMenu.Create; B := TMenu.Create; C := TMenu.Create;
  D.NextScreen := @A;
  Check(D.InitializeNextScreen, 'first target not initialized');
  Check(D.InitializeNextScreen and (A.Calls=1), 'same target initialized twice');
  D.NextScreen := @B;
  Check(D.InitializeNextScreen and (B.Calls=1), 'changed target skipped');
  A.Redirect := @C; D.NextScreen := @A; D.FadeStartTime := 42;
  Check(not D.InitializeNextScreen, 'reentrant redirect was accepted as initialized');
  Check((C.Calls=0) and (D.ShownScreen=nil) and (D.FadeStartTime=0), 'redirect state not reset');
  Check(D.InitializeNextScreen and (C.Calls=1), 'replacement target skipped');
  D.NextScreen := nil;
  Check(not D.InitializeNextScreen, 'nil target initialized');
  A.Free; B.Free; C.Free; D.Free;
  WriteLn('PASS: once per target, target change, reentrant OnShow and nil target');
end.
'''
        self.run_harness(harness)

    def test_shutdown_fade_keeps_its_start_time(self):
        source = (Path(__file__).resolve().parents[1] / 'src/menu/UDisplay.pas').read_text()
        reset = next(line.strip() for line in source.splitlines()
                     if '(ShownScreen <> NextScreen)' in line)
        self.run_harness('''program ShutdownFade;
{$mode delphi}
uses SysUtils;
var S, I, ShownScreen, NextScreen: integer;
    BlackScreen: boolean; FadeStartTime: cardinal;
procedure ResetTarget;
begin
''' + reset + '''
end;
begin
  S := 1; ShownScreen := 0; NextScreen := 1;
  BlackScreen := true; FadeStartTime := 42;
  for I := 1 to 100 do ResetTarget;
  if FadeStartTime <> 42 then raise Exception.Create('Shutdown fade keeps restarting');
  BlackScreen := false; ResetTarget;
  if FadeStartTime <> 0 then raise Exception.Create('Redirect did not restart');
  FadeStartTime := 42; ShownScreen := NextScreen; ResetTarget;
  if FadeStartTime <> 42 then raise Exception.Create('Initialized target restarted');
  ShownScreen := 0; S := 2; ResetTarget;
  if FadeStartTime <> 42 then raise Exception.Create('Second screen restarted');
  WriteLn('PASS: shutdown fade, redirected target and second screen');
end.
''')

    def test_aborted_unfinished_screen_is_not_drawn_for_snapshot(self):
        source = (Path(__file__).resolve().parents[1] / 'src/menu/UDisplay.pas').read_text()
        guard = next(line.strip() for line in source.splitlines()
                     if 'if CurrentScreen.ShowFinish then CurrentScreen.Draw;' in line)
        self.run_harness('''program AbortedSnapshot;
{$mode delphi}
uses SysUtils;
type TMenu = class
  ShowFinish: boolean;
  Calls: integer;
  procedure Draw;
end;
procedure TMenu.Draw;
begin
  if not ShowFinish then raise Exception.Create('Drew an uninitialized screen');
  Inc(Calls);
end;
var CurrentScreen: TMenu;
procedure Capture;
begin
''' + guard + '''
end;
begin
  CurrentScreen := TMenu.Create;
  Capture;
  if CurrentScreen.Calls <> 0 then raise Exception.Create('Captured aborted screen');
  CurrentScreen.ShowFinish := true;
  Capture;
  if CurrentScreen.Calls <> 1 then raise Exception.Create('Skipped valid source');
  CurrentScreen.Free;
  WriteLn('PASS: aborted screen omitted, initialized screen captured');
end.
''')
