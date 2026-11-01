"""Exercise the production catalog handoff without menus or media."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class LibraryPublishTests(unittest.TestCase):
    def test_snapshot_ownership_scope_and_failure(self):
        fpc = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not fpc:
            self.skipTest('Free Pascal is not installed')
        source = (Path(__file__).resolve().parents[1] / 'src/base/USongs.pas').read_text(encoding='utf-8')
        method = 'function TSongs.PublishRefresh' + source.split('function TSongs.PublishRefresh', 1)[1].split('procedure TSongs.ReplayDeferredReload;', 1)[0]
        refresh = (Path(__file__).resolve().parents[1] / 'src/base/ULibraryRefresh.pas').read_text(encoding='utf-8')
        covers_method = 'function TLibraryRefresh.Covers' + refresh.split('function TLibraryRefresh.Covers', 1)[1].split('procedure TLibraryRefresh.ReadSong', 1)[0]
        catalog_methods = 'function TCatSongs.VisibleSongs' + source.split('function TCatSongs.VisibleSongs', 1)[1].split('function TCatSongs.FilterMask', 1)[0]
        harness = r'''program Probe; {$mode Delphi}
uses SysUtils, Classes;
type
  IPath = interface function Append(const N: IPath): IPath; function Name: string; function IsChildOf(const Parent: IPath; Direct: boolean): boolean; end;
  TPath = class(TInterfacedObject, IPath)
    S: string; constructor Create(const N: string);
    function Append(const N: IPath): IPath; function Name: string;
    function IsChildOf(const Parent: IPath; Direct: boolean): boolean;
  end;
  TSong = class
    Path, FileName: IPath;
    Visible: boolean; VisibleIndex: integer;
    constructor Create(const N: string); destructor Destroy; override;
  end;
  TLibraryRefresh = class
    Roots, Skipped: array of IPath;
    Entries, Seen, Failed: TStringList; Failure: string;
    constructor Create; destructor Destroy; override;
    class function Key(const N: IPath): string;
    function Covers(const Name: IPath): boolean;
    procedure WaitFor;
  end;
  TCatSongs = class
    Song: array of TSong; LastVisChecked, LastVisIndex: integer;
    function VisibleSongs: integer;
    function VisibleIndex(Index: integer): integer;
  end;
  TSongs = class
    fFailedSongFiles: TStringList;
    SongList: TList; fRefresh: TLibraryRefresh; fProcessing: boolean;
    function RefreshReady: boolean;
    function PublishRefresh(out Retired: TList): boolean;
  end;
var Live: integer = 0;
constructor TPath.Create(const N: string); begin S := N; end;
function TPath.Append(const N: IPath): IPath; begin Result := TPath.Create(S + N.Name); end;
function TPath.Name: string; begin Result := S; end;
function TPath.IsChildOf(const Parent: IPath; Direct: boolean): boolean;
begin Result := Pos(Parent.Name + '/', S) = 1; end;
constructor TSong.Create(const N: string); begin Inc(Live); Path := TPath.Create(''); FileName := TPath.Create(N); end;
destructor TSong.Destroy; begin Dec(Live); inherited; end;
constructor TLibraryRefresh.Create; begin Entries := TStringList.Create; Entries.Sorted := true; Seen := TStringList.Create; Failed := TStringList.Create; end;
destructor TLibraryRefresh.Destroy;
var I: integer; begin for I := 0 to Entries.Count - 1 do Entries.Objects[I].Free; Entries.Free; Seen.Free; Failed.Free; inherited; end;
class function TLibraryRefresh.Key(const N: IPath): string; begin Result := N.Name; end;

function Path(const N: UTF8String): IPath; begin Result := TPath.Create(N); end;
procedure TLibraryRefresh.WaitFor; begin end;
function TSongs.RefreshReady: boolean; begin Result := fRefresh <> nil; end;
''' + method + covers_method + catalog_methods + r'''
procedure Check(B: boolean; const M: string); begin if not B then raise Exception.Create(M); end;
procedure Release(L: TList); var I: integer; begin for I := 0 to L.Count - 1 do TObject(L[I]).Free; L.Free; end;
var S: TSongs; Old, Incomplete, Outside, Deleted, Replacement, Added, Linked: TSong; Retired: TList; Cat: TCatSongs;
begin
  Cat := TCatSongs.Create;
  Check((Cat.VisibleSongs = 0) and (Cat.VisibleIndex(-1) = -1), 'empty catalog indexed a missing song');
  Cat.Free;
  S := TSongs.Create; S.SongList := TList.Create; S.fFailedSongFiles := TStringList.Create;
  S.fFailedSongFiles.Add('outside/rejected'); S.fFailedSongFiles.Add('scope/fixed');
  S.fFailedSongFiles.Add('scope/gone'); S.fFailedSongFiles.Add('scope/writing');
  Old := TSong.Create('scope/old'); Incomplete := TSong.Create('scope/incomplete');
  Outside := TSong.Create('outside/keep'); Deleted := TSong.Create('scope/deleted');
  Linked := TSong.Create('scope/link/song'); S.SongList.Add(Linked);
  S.SongList.Add(Old); S.SongList.Add(Incomplete); S.SongList.Add(Outside); S.SongList.Add(Deleted);
  S.fRefresh := TLibraryRefresh.Create; S.fProcessing := true;
  SetLength(S.fRefresh.Roots, 1); S.fRefresh.Roots[0] := TPath.Create('scope');
  SetLength(S.fRefresh.Skipped, 1); S.fRefresh.Skipped[0] := TPath.Create('scope/link');
  Replacement := TSong.Create('scope/old'); Added := TSong.Create('scope/new');
  S.fRefresh.Entries.AddObject('scope/old', Replacement); S.fRefresh.Entries.AddObject('scope/new', Added);
  S.fRefresh.Seen.Add('scope/incomplete');
  S.fRefresh.Seen.Add('scope/writing'); S.fRefresh.Seen.Add('scope/bad');
  S.fRefresh.Failed.Add('scope/bad');
  Check(S.PublishRefresh(Retired), 'publish failed');
  Check((S.SongList.Count = 5) and (Retired.Count = 2), 'wrong counts');
  Check((S.SongList.IndexOf(Replacement) >= 0) and (S.SongList.IndexOf(Added) >= 0), 'new objects not transferred');
  Check((S.SongList.IndexOf(Incomplete) >= 0) and (S.SongList.IndexOf(Outside) >= 0), 'valid old object lost');
  Check(S.SongList.IndexOf(Linked) >= 0, 'skipped linked subtree was deleted');
  Check((Retired.IndexOf(Old) >= 0) and (Retired.IndexOf(Deleted) >= 0), 'old snapshot not retained');
  Check((Live = 7) and (S.fRefresh = nil) and not S.fProcessing, 'ownership or completion state wrong');
  Check((S.fFailedSongFiles.Count = 3) and (S.fFailedSongFiles.IndexOf('outside/rejected') >= 0) and
    (S.fFailedSongFiles.IndexOf('scope/writing') >= 0) and (S.fFailedSongFiles.IndexOf('scope/bad') >= 0), 'failed-file scope was not preserved');
  Release(Retired);
  S.fRefresh := TLibraryRefresh.Create; S.fRefresh.Failure := 'unplugged root';
  S.fRefresh.Entries.AddObject('scope/bad', TSong.Create('scope/bad'));
  Check(not S.PublishRefresh(Retired), 'failed scan published');
  Check((Retired = nil) and (Live = 5) and (S.SongList.Count = 5), 'failed scan changed catalog or leaked');
  Check(S.fFailedSongFiles.Count = 3, 'failed scan changed rejected-file count');
  S.fFailedSongFiles.Free; Release(S.SongList); S.Free; Check(Live = 0, 'leaked song'); WriteLn('PASS');
end.
'''
        with tempfile.TemporaryDirectory() as temp:
            d = Path(temp)
            (d / 'probe.pas').write_text(harness, encoding='utf-8')
            result = subprocess.run([fpc, '-Mdelphi', '-Ciro', '-gl', '-FE' + str(d), str(d / 'probe.pas')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(d / ('probe.exe' if os.name == 'nt' else 'probe'))], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS', result.stdout)
