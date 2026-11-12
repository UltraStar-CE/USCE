"""Test production scan error handling against native directory enumeration."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class LibraryScanTests(unittest.TestCase):
    def test_empty_unreadable_and_interrupted_enumeration(self):
        fpc = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not fpc:
            self.skipTest('Free Pascal is not installed')
        source = (Path(__file__).resolve().parents[1] / 'src/base/ULibraryRefresh.pas').read_text(encoding='utf-8')
        helpers = 'procedure ClearSearchError;' + source.split('procedure ClearSearchError;', 1)[1].split('constructor TLibraryRefresh.Create', 1)[0]
        scan = 'procedure TLibraryRefresh.Scan' + source.split('procedure TLibraryRefresh.Scan', 1)[1].split('procedure TLibraryRefresh.Execute;', 1)[0]
        harness = r'''program Probe; {$mode Delphi}
uses SysUtils, Classes, {$IFDEF MSWINDOWS}Windows{$ELSE}BaseUnix{$ENDIF};
type
 IPath = interface
  function Append(const N: IPath): IPath; overload;
  function Append(const N: string): IPath; overload;
  function IsFile: boolean; function IsDirectory: boolean;
  function GetExtension: IPath; function ToUTF8: string;
  function Equals(const N: string; IgnoreCase: boolean = false): boolean;
 end;
 TPath = class(TInterfacedObject, IPath)
  S: string; constructor Create(const N: string);
  function Append(const N: IPath): IPath; overload;
  function Append(const N: string): IPath; overload;
  function IsFile: boolean; function IsDirectory: boolean;
  function GetExtension: IPath; function ToUTF8: string;
  function Equals(const N: string; IgnoreCase: boolean = false): boolean; reintroduce;
 end;
 TSytemSearchRec = TUnicodeSearchRec;
 TFS = class
  DenyOpen, FailNext: boolean; OpenHandles: integer;
  function FindFirst(const N: IPath; Attr: integer; var R: TSytemSearchRec): integer;
  function FindNext(var R: TSytemSearchRec): integer;
  procedure FindClose(var R: TSytemSearchRec);
 end;
 TLibraryRefresh = class
  Terminated: boolean; Skipped: array of IPath; Count: integer;
  procedure ReadSong(const N: IPath); procedure Scan(const Name: IPath);
 end;
var FileSystem: TFS;
function Path(const N: string): IPath; begin Result := TPath.Create(N); end;
constructor TPath.Create(const N: string); begin S := N; end;
function TPath.Append(const N: IPath): IPath; begin Result := Append(N.ToUTF8); end;
function TPath.Append(const N: string): IPath; begin Result := Path(IncludeTrailingPathDelimiter(S) + N); end;
function TPath.IsFile: boolean; begin Result := FileExists(S); end;
function TPath.IsDirectory: boolean; begin Result := DirectoryExists(S); end;
function TPath.GetExtension: IPath; begin Result := Path(ExtractFileExt(S)); end;
function TPath.ToUTF8: string; begin Result := S; end;
function TPath.Equals(const N: string; IgnoreCase: boolean): boolean;
begin if IgnoreCase then Result := SameText(S,N) else Result := S=N; end;
procedure FailOS(Code: integer); begin {$IFDEF MSWINDOWS}SetLastError(Code);{$ELSE}fpSetErrno(Code);{$ENDIF} end;
function TFS.FindFirst(const N: IPath; Attr: integer; var R: TSytemSearchRec): integer;
begin
 if DenyOpen and (Pos('blocked', N.ToUTF8)>0) then begin {$IFDEF MSWINDOWS}FailOS(5); Exit(5);{$ELSE}FailOS(13); Exit(-1);{$ENDIF} end;
 Result := SysUtils.FindFirst(UnicodeString(N.ToUTF8), Attr, R);
 if Result=0 then Inc(OpenHandles);
end;
function TFS.FindNext(var R: TSytemSearchRec): integer;
begin
 if FailNext then begin {$IFDEF MSWINDOWS}FailOS(30); Exit(30);{$ELSE}FailOS(5); Exit(-1);{$ENDIF} end;
 Result := SysUtils.FindNext(R);
end;
procedure TFS.FindClose(var R: TSytemSearchRec); begin SysUtils.FindClose(R); Dec(OpenHandles); end;
procedure TLibraryRefresh.ReadSong(const N: IPath); begin Inc(Count); end;
''' + helpers + scan + r'''
procedure Check(B: boolean; const M: string); begin if not B then raise Exception.Create(M); end;
var S: TLibraryRefresh; Root, Blocked: string; Failed: boolean;
begin
 Root := ParamStr(1); FileSystem := TFS.Create; S := TLibraryRefresh.Create;
 try
  S.Scan(Path(Root + '/empty')); Check(S.Count=0, 'empty directory failed');
  S.Scan(Path(Root + '/full')); Check(S.Count=1, 'ordinary directory failed');
  Blocked := Root + '/full/blocked'; ForceDirectories(Blocked);
  {$IFDEF UNIX}if fpGetuid=0 then FileSystem.DenyOpen := true else fpChmod(PChar(Blocked),0);{$ELSE}FileSystem.DenyOpen := true;{$ENDIF}
  try
   Failed := false; try S.Scan(Path(Root+'/full')); except on E: Exception do Failed := true; end;
   Check(Failed, 'permission failure appeared empty');
  finally
   {$IFDEF UNIX}fpChmod(PChar(Blocked),$1C0);{$ENDIF}
   FileSystem.DenyOpen := false;
  end;
  FileSystem.FailNext := true;
  Failed := false; try S.Scan(Path(Root+'/full')); except on E: Exception do Failed := true; end;
  Check(Failed, 'interrupted enumeration succeeded');
  Check(FileSystem.OpenHandles=0, 'search handle leaked'); WriteLn('PASS');
 finally S.Free; FileSystem.Free; end;
end.
'''
        with tempfile.TemporaryDirectory() as temp:
            d = Path(temp)
            (d / 'empty').mkdir()
            (d / 'full').mkdir()
            (d / 'full/song.txt').write_text('fixture')
            (d / 'probe.pas').write_text(harness, encoding='utf-8')
            result = subprocess.run([fpc, '-Mdelphi', '-Ciro', '-gl', '-FE' + str(d), str(d / 'probe.pas')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(d / ('probe.exe' if os.name == 'nt' else 'probe')), str(d)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS', result.stdout)
