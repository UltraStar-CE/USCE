"""Compile and exercise the production frame pacer with an injected clock."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FramePacerTests(unittest.TestCase):
    def test_deadlines_fractional_rates_stalls_and_changes(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        root = Path(__file__).resolve().parents[1]
        harness = '''program PacingTest;
{$mode Delphi}
uses SysUtils, UFramePacer;
type TFakePacer = class(TFramePacer)
  Now: UInt64;
  Waits: integer;
  function Clock: UInt64; override;
  procedure Wait(Milliseconds: double); override;
end;
function TFakePacer.Clock: UInt64;
begin Result := Now; end;
procedure TFakePacer.Wait(Milliseconds: double);
begin Inc(Waits); Inc(Now, Round(Milliseconds)); end;
procedure Check(Value: boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var P: TFakePacer; I, PreviousWaits: integer;
begin
  P := TFakePacer.Create(1000);
  try
    for I := 1 to 600 do P.WaitForFrame(60);
    Check(P.Now = 10000, 'fractional 60 fps deadline drift');
    Check(P.Waits = 600, 'missing blocking waits');
    P.Now := P.Now + 5000; PreviousWaits := P.Waits;
    P.WaitForFrame(60);
    Check(P.Waits = PreviousWaits, 'late frame was delayed again');
    P.WaitForFrame(60);
    Check(P.Waits = PreviousWaits + 1, 'catch-up burst after a stall');
    P.Now := 20000;
    for I := 1 to 50 do P.WaitForFrame(50);
    Check(P.Now = 21000, '50 fps cap');
    for I := 1 to 30 do P.WaitForFrame(30);
    Check(P.Now = 22000, '30 fps cap after a change');
    for I := 1 to 200 do P.WaitForFrame(200);
    Check(P.Now = 23000, 'high frame cap');
    P.WaitForFrame(0);
    Check(P.Now = 24000, 'invalid cap must remain bounded');
  finally P.Free; end;
  WriteLn('PASS: accurate rates, blocking waits, late frames and cap changes');
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pacing_test.pas'
            path.write_text(harness)
            # Only timing is mocked; deadline arithmetic is the real unit.
            (Path(directory) / 'SDL2.pas').write_text('''unit SDL2;
{$mode Delphi}
interface
function SDL_GetPerformanceFrequency: UInt64;
function SDL_GetPerformanceCounter: UInt64;
procedure SDL_Delay(MS: cardinal);
implementation
function SDL_GetPerformanceFrequency: UInt64; begin Result := 1000; end;
function SDL_GetPerformanceCounter: UInt64; begin Result := 0; end;
procedure SDL_Delay(MS: cardinal); begin end;
end.
''')
            result = subprocess.run([compiler, '-B', '-Mdelphi', '-Ciro',
                '-Fu' + directory, '-Fu' + str(root / 'src/base'),
                '-FU' + directory, '-FE' + directory, str(path)], cwd=directory,
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))],
                           check=True, timeout=5)
