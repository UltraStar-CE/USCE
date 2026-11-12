import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest


class MenuVideoContinuityTests(unittest.TestCase):
    def test_shared_decoder_clock_survives_transitions_and_releases_before_renderer(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        root = pathlib.Path(__file__).resolve().parents[1]
        source = (root / 'src/menu/UMenuBackgroundVideo.pas').read_text(encoding='utf-8')
        state = re.search(r'TMenuVideoState = class.*?\n  end;', source, re.S).group()
        implementation = source.split('var CachedMenuVideo: TMenuVideoState;', 1)[1].split('constructor TMenuBackgroundVideo.Create', 1)[0]
        harness = '''program MenuVideoTest;
{$mode delphi}
var Clock: real; Opens, LiveVideos, FreedTimers: integer;
type
  IPath = class
    Name: string;
    function Equals(Other: IPath): boolean; reintroduce;
  end;
  IVideo = interface
    procedure SetLoop(Value: boolean); procedure Play;
    property Loop: boolean write SetLoop;
  end;
  TMockVideo = class(TInterfacedObject, IVideo)
    constructor Create; destructor Destroy; override;
    procedure SetLoop(Value: boolean); procedure Play;
  end;
  TMockPlayback = class function Open(FileName: IPath): IVideo; end;
  TRelativeTimer = class
    Elapsed, Started: real; Running: boolean;
    procedure Start; procedure Pause; function GetTime: real;
    destructor Destroy; override;
  end;
''' + state + '''
var CachedMenuVideo: TMenuVideoState; VideoPlayback: TMockPlayback;
function IPath.Equals(Other: IPath): boolean;
begin Result := Name = Other.Name; end;
constructor TMockVideo.Create; begin inherited; Inc(LiveVideos); end;
destructor TMockVideo.Destroy; begin Dec(LiveVideos); inherited; end;
procedure TMockVideo.SetLoop(Value: boolean); begin end;
procedure TMockVideo.Play; begin end;
function TMockPlayback.Open(FileName: IPath): IVideo;
begin Inc(Opens); Result := TMockVideo.Create; end;
procedure TRelativeTimer.Start;
begin if not Running then begin Started := Clock; Running := true; end; end;
procedure TRelativeTimer.Pause;
begin if Running then begin Elapsed := GetTime; Running := false; end; end;
function TRelativeTimer.GetTime: real;
begin Result := Elapsed; if Running then Result := Result + Clock - Started; end;
destructor TRelativeTimer.Destroy; begin Inc(FreedTimers); inherited; end;
''' + implementation + '''
procedure Check(Value: boolean; Code: integer);
begin if not Value then Halt(Code); end;
var PathA, PathA2, PathB, PathC: IPath; A, B, C: TMenuVideoState;
begin
  VideoPlayback := TMockPlayback.Create;
  PathA := IPath.Create; PathA.Name := 'a'; PathA2 := IPath.Create; PathA2.Name := 'a';
  PathB := IPath.Create; PathB.Name := 'b'; PathC := IPath.Create; PathC.Name := 'c';
  A := AcquireMenuVideo(PathA); Clock := 1;
  B := AcquireMenuVideo(PathA2);
  Check((A = B) and (Opens = 1) and (A.Timer.GetTime = 1), 1);
  ReleaseMenuVideo(A); Clock := 2; Check(B.Timer.GetTime = 2, 2);
  ReleaseMenuVideo(B); Clock := 12; A := AcquireMenuVideo(PathA);
  Check((Opens = 1) and (A.Timer.GetTime = 2), 3);
  ReleaseMenuVideo(A);
  B := AcquireMenuVideo(PathB); Check((FreedTimers = 1) and (LiveVideos = 1), 4);
  C := AcquireMenuVideo(PathC); Check((Opens = 3) and (LiveVideos = 2), 5);
  ReleaseMenuVideo(B); Check((FreedTimers = 2) and (LiveVideos = 1), 6);
  ClearMenuVideoCache(true); Check(LiveVideos = 0, 7);
  ReleaseMenuVideo(C); Check(FreedTimers = 3, 8); ClearMenuVideoCache(true);
  PathA.Free; PathA2.Free; PathB.Free; PathC.Free; VideoPlayback.Free;
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'menuvideo.pas'
            path.write_text(harness, encoding='utf-8')
            subprocess.run([compiler, '-Mdelphi', '-Ciro', str(path)], cwd=directory, check=True, capture_output=True)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))], check=True)


if __name__ == '__main__':
    unittest.main()
