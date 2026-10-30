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

    def test_outline_uses_physical_scale_for_wide_and_tall_buttons(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        source = (Path(__file__).resolve().parents[1] / 'src/menu/UMenuButton.pas').read_text()
        geometry = source.split('  // Shape fractions use physical pixels, matching the renderer.\n', 1)[1].split('  FocusTexture.Alpha :=', 1)[0]
        harness = '''program FocusGeometry;
{$mode delphi}
uses Math, SysUtils;
const lsStretch = 0;
type TTexture = class
  W, H, Z, CornerRadius, OutlineWidth: single;
  ScaleMode: integer;
end;
var FocusTexture, Texture: TTexture;
    ShortSide, PixelScale, UnitW, UnitH, FocusRadius, FocusWidth, SX, SY: single;
function GetLayoutScaleX: single; begin Result := SX; end;
function GetLayoutScaleY: single; begin Result := SY; end;
procedure Calculate;
begin
''' + geometry + '''
end;
procedure Check(W, H, ScaleX, ScaleY, UX, UY: single);
var Expected: single;
begin
  SX := ScaleX; SY := ScaleY; UnitW := UX; UnitH := UY;
  FocusTexture.W := W * UX; FocusTexture.H := H * UY;
  Calculate;
  Expected := Min(UX * SX, UY * SY);
  if Abs(FocusTexture.OutlineWidth * ShortSide - 3 * Expected) > 0.001 then
    raise Exception.Create('Outline width changes with button aspect ratio');
  if Abs(FocusTexture.CornerRadius * ShortSide - 12 * Expected) > 0.001 then
    raise Exception.Create('Corner radius changes with button aspect ratio');
end;
begin
  FocusTexture := TTexture.Create; Texture := TTexture.Create;
  FocusWidth := 3; FocusRadius := 12;
  Check(100, 50, 2.4, 1.8, 0.75, 1);
  Check(50, 100, 2.4, 1.8, 0.75, 1);
  Check(100, 50, 3.2, 1.8, 0.5625, 1);
  Check(50, 100, 3.2, 1.8, 0.5625, 1);
  Check(100, 50, 2, 2, 1, 1);
  Check(50, 100, 2, 2, 1, 1);
  Check(100, 50, 2.4, 1.8, 1, 1);
  FocusTexture.W := -1; FocusTexture.H := 10;
  FocusTexture.OutlineWidth := 0; Calculate;
  if FocusTexture.OutlineWidth <> 0 then
    raise Exception.Create('Inverted inset bounds must not produce an outline');
  FocusTexture.Free; Texture.Free;
  WriteLn('PASS: uniform 16:9, 21:9, 4:3 and stretch outline geometry');
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'focus_geometry.pas'
            path.write_bytes(harness.encode())
            result = subprocess.run([compiler, '-Mdelphi', '-Ciro', str(path)], cwd=directory,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))], check=True)
