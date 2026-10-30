"""Run the production bounded handoff with a deliberately slow decoder."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class CoverDecodeTest(unittest.TestCase):
    def test_handoff_cancellation_failure_and_shutdown(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            shutil.copyfile(Path(__file__).resolve().parents[1] / 'src/base/UCoverDecode.pas', d / 'UCoverDecode.pas')
            (d / 'SDL2.pas').write_text("""unit SDL2; {$mode Delphi} interface
            type PSDL_Surface = ^integer;
            var Live: longint = 0;
            procedure SDL_FreeSurface(P: PSDL_Surface);
            implementation
            procedure SDL_FreeSurface(P: PSDL_Surface);
            begin if P <> nil then begin Dispose(P); InterlockedDecrement(Live); end; end;
            end.""")
            (d / 'UPath.pas').write_text("""unit UPath; {$mode Delphi} interface
            type IPath = interface function IsUnset: boolean; function ToUTF8: string; end;
            TPath = class(TInterfacedObject, IPath)
              S: string; constructor Create(const N: string);
              function IsUnset: boolean; function ToUTF8: string;
            end;
            implementation
            constructor TPath.Create(const N: string); begin S := N; end;
            function TPath.IsUnset: boolean; begin Result := S = ''; end;
            function TPath.ToUTF8: string; begin Result := S; end;
            end.""")
            (d / 'URenderer.pas').write_text("""unit URenderer; {$mode Delphi} interface
            uses SDL2, UPath;
            const TEXTURE_TYPE_PLAIN = 0; DEFAULT_TEXTURE_LIMIT = 4096;
            var Calls: longint = 0;
            function PrepareTextureSurface(const N: IPath; T, C, L: integer): PSDL_Surface;
            implementation uses Classes, SysUtils;
            function PrepareTextureSurface(const N: IPath; T, C, L: integer): PSDL_Surface;
            begin InterlockedIncrement(Calls); Sleep(35);
              if N.ToUTF8 = 'bad' then raise Exception.Create('bad image');
              New(Result); Result^ := StrToInt(N.ToUTF8); InterlockedIncrement(Live);
            end;
            end.""")
            (d / 'probe.pas').write_text("""program Probe; {$mode Delphi}
            uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils, UCoverDecode, UPath, SDL2, URenderer;
            var L: TCoverDecode; P: PSDL_Surface; N, Bad: IPath; Started: QWord; I, Before: integer;
            procedure Check(B: boolean; const M: string); begin if not B then raise Exception.Create(M); end;
            function Await(const Name: IPath): PSDL_Surface;
            var T: QWord;
            begin T := GetTickCount64; repeat L.BeginFrame;
              if L.Poll(Name, Result) then Exit; L.EndFrame; Sleep(1);
              Check(GetTickCount64 - T < 3000, 'handoff timed out'); until false;
            end;
            begin
              L := TCoverDecode.Create(4096);
              try
                N := TPath.Create('1'); Started := GetTickCount64;
                for I := 1 to 100 do Check(not L.Poll(N, P), 'unexpected early image');
                Check(GetTickCount64 - Started < 25, 'request blocked on decode');
                P := Await(N); Check(P^ = 1, 'wrong image'); SDL_FreeSurface(P);
                Check(Calls = 1, 'duplicate requests decoded');
                N := TPath.Create('2'); L.Poll(N, P); Sleep(5); L.Clear;
                N := TPath.Create('3'); P := Await(N); Check(P^ = 3, 'stale result published'); SDL_FreeSurface(P);
                Bad := TPath.Create('bad'); L.Poll(Bad, P); Sleep(80); Before := Calls;
                for I := 1 to 100 do L.Poll(Bad, P); Sleep(80);
                Check(Calls = Before, 'failed image retried each frame');
                for I := 4 to 1000 do L.Poll(TPath.Create(IntToStr(I)), P);
                L.Clear; L.BeginFrame; N := TPath.Create('1001'); P := Await(N);
                Check(P^ = 1001, 'queue did not recover'); SDL_FreeSurface(P);
                N := TPath.Create('1002'); L.Poll(N, P); Sleep(5);
              finally L.Free; end;
              Check(Live = 0, 'surface leaked'); WriteLn('PASS');
            end.""")
            subprocess.run([compiler, '-Mdelphi', '-Ciro', '-gl', '-Fu' + str(d), '-FE' + str(d), str(d / 'probe.pas')], check=True, capture_output=True, text=True)
            result = subprocess.run([str(d / ('probe.exe' if os.name == 'nt' else 'probe'))], check=True, capture_output=True, text=True, timeout=10)
            self.assertIn('PASS', result.stdout)
