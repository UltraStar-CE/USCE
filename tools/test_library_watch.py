"""Exercise real OS notifications, without the game, media or external libraries."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class LibraryWatchTests(unittest.TestCase):
    def test_native_add_change_rename_delete_and_new_subdirectories(self):
        fpc = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not fpc:
            self.skipTest('Free Pascal is not installed')
        source = Path(__file__).resolve().parents[1] / 'src/base'
        harness = r'''program WatchProbe;
{$mode Delphi}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils, Classes, ULibraryWatch;
var Watch: TLibraryWatch; Roots, Changes: TStringList; Root, Sub, Other: string;
  Full: boolean; Error: string;
procedure Check(OK: boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
procedure WriteFile(const Name, Text: string);
var S: TStringList;
begin S := TStringList.Create; try S.Text := Text; S.SaveToFile(Name); finally S.Free; end; end;
function CompareFileName(const A, B: string): integer;
begin
  {$IFDEF MSWINDOWS}Result := CompareText(A, B);{$ELSE}Result := CompareStr(A, B);{$ENDIF}
end;
procedure WaitChange(const Target: string; Initial: boolean = false);
var Start: QWord; I: integer; Found: boolean;
begin
  Start := GetTickCount64;
  repeat
    if Watch.TakeChanges(Changes, Full, Error) then
    begin
      Check(Error = '', Error);
      Found := Full and Initial;
      for I := 0 to Changes.Count - 1 do
        if (CompareFileName(Target, Changes[I]) = 0) or
           (CompareFileName(Copy(Changes[I], 1, Length(IncludeTrailingPathDelimiter(Target))), IncludeTrailingPathDelimiter(Target)) = 0) or
           (CompareFileName(Copy(Target, 1, Length(IncludeTrailingPathDelimiter(Changes[I]))), IncludeTrailingPathDelimiter(Changes[I])) = 0) then Found := true;
      Check(Found, 'unexpected event scope: ' + Changes.Text + ' for ' + Target);
      Exit;
    end;
    Check(Error = '', Error);
    Sleep(20);
  until GetTickCount64 - Start > 8000;
  raise Exception.Create('missing event: ' + Target);
end;
procedure Quiet(const Phase: string);
var Start: QWord;
begin
  Start := GetTickCount64;
  repeat
    if Watch.TakeChanges(Changes, Full, Error) then
      raise Exception.Create('idle watcher generated another scan ' + Phase + ': ' + Changes.Text + ' full=' + BoolToStr(Full, true));
    Check(Error = '', Error);
    Sleep(20);
  until GetTickCount64 - Start > 650;
end;
procedure SettleStartup;
var Start, QuietSince: QWord;
begin
  // FSEvents can deliver root-creation events after the initial recovery scan,
  // even after a synchronous flush. Require bounded settling, then test idle.
  Start := GetTickCount64;
  QuietSince := Start;
  repeat
    if Watch.TakeChanges(Changes, Full, Error) then QuietSince := GetTickCount64;
    Check(Error = '', Error);
    if GetTickCount64 - QuietSince >= 1000 then Exit;
    Check(GetTickCount64 - Start < 8000, 'watcher did not settle after startup');
    Sleep(20);
  until false;
end;
begin
  Root := ExpandFileName(ParamStr(1));
  Sub := Root + PathDelim + 'new' + PathDelim + 'nested';
  Other := ExtractFileDir(Root) + PathDelim + 'unrelated';
  ForceDirectories(Root); ForceDirectories(Other);
  Roots := TStringList.Create; Changes := TStringList.Create;
  Roots.Add(Root);
  {$IFDEF LINUX}
  ForceDirectories(Root + '/Artist'); ForceDirectories(Root + '/artist');
  ForceDirectories(Root + '-Case'); ForceDirectories(Root + '-case');
  Roots.Add(Root + '-Case'); Roots.Add(Root + '-case');
  {$ENDIF}
  Watch := TLibraryWatch.Create(Roots);
  try
    WaitChange(Root, true); SettleStartup; Quiet('after startup');
    {$IFDEF LINUX}
    WriteFile(Root + '/Artist/song.txt', 'upper directory'); WaitChange(Root + '/Artist/song.txt');
    WriteFile(Root + '/artist/song.txt', 'lower directory'); WaitChange(Root + '/artist/song.txt');
    WriteFile(Root + '-Case/song.txt', 'upper root'); WaitChange(Root + '-Case/song.txt');
    WriteFile(Root + '-case/song.txt', 'lower root'); WaitChange(Root + '-case/song.txt');
    DeleteFile(Root + '/Artist/song.txt'); DeleteFile(Root + '/artist/song.txt');
    RemoveDir(Root + '/Artist'); RemoveDir(Root + '/artist'); WaitChange(Root);
    {$ENDIF}
    WriteFile(Root + PathDelim + 'song.txt', 'first'); WaitChange(Root);
    WriteFile(Root + PathDelim + 'song.txt', 'updated'); WaitChange(Root);
    Changes.LoadFromFile(Root + PathDelim + 'song.txt'); Quiet('after reading'); // reading is not a mutation
    ForceDirectories(Sub);
    WriteFile(Sub + PathDelim + 'duet.txt', 'copied with nested directory'); WaitChange(Sub);
    WriteFile(Sub + PathDelim + 'duet.txt', 'later modification'); WaitChange(Sub);
    Check(RenameFile(Sub, Sub + '-renamed'), 'rename failed'); WaitChange(ExtractFileDir(Sub));
    Sub := Sub + '-renamed';
    WriteFile(Sub + PathDelim + 'duet.txt', 'after rename'); WaitChange(Sub);
    Check(DeleteFile(Sub + PathDelim + 'duet.txt'), 'delete failed'); WaitChange(Sub);
    Check(RemoveDir(Sub), 'rmdir failed'); WaitChange(ExtractFileDir(Sub));
    WriteFile(Other + PathDelim + 'not-a-song.txt', 'outside library'); Quiet('after outside file');
    ForceDirectories(Other + '-sibling'); Quiet('after outside directory creation');
    Check(RemoveDir(Other + '-sibling'), 'outside sibling remove failed'); Quiet('after outside directory removal');
    Check(DeleteFile(Root + PathDelim + 'song.txt'), 'root file delete failed'); WaitChange(Root);
    Check(RemoveDir(ExtractFileDir(Sub)), 'nested parent remove failed'); WaitChange(Root);
    Check(RemoveDir(Root), 'root remove failed'); WaitChange(Root, true);
    ForceDirectories(Root); WaitChange(Root, true);
    WriteFile(Root + PathDelim + 'restored.txt', 'after root recreation'); WaitChange(Root);
    Check(RenameFile(Root, Root + '-moved'), 'root rename failed'); WaitChange(Root, true);
    ForceDirectories(Root); WaitChange(Root, true);
    WriteFile(Root + PathDelim + 'fresh.txt', 'new inode at configured root'); WaitChange(Root);
    WriteFile(Root + '-moved' + PathDelim + 'old-root.txt', 'no longer in library'); Quiet('after moved-root file');
    Quiet('at shutdown');
    Writeln('PASS native add/change/rename/delete, new nested watches, root recreation, idle and outside-library isolation');
  finally Watch.Free; Roots.Free; Changes.Free; end;
end.
'''
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            probe = folder / 'watchprobe.pas'
            probe.write_text(harness, encoding='utf-8')
            compiled = subprocess.run([fpc, '-Fu' + str(source), '-FU' + temp,
                                       '-FE' + temp, str(probe)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            exe = folder / ('watchprobe.exe' if os.name == 'nt' else 'watchprobe')
            result = subprocess.run([str(exe), str(folder / 'songs')], capture_output=True,
                                    text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS native', result.stdout)


if __name__ == '__main__':
    unittest.main()
