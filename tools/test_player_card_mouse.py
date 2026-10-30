"""Exercise production card mouse dispatch before the inherited Return action."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class PlayerCardMouseTests(unittest.TestCase):
    def test_card_editors_do_not_submit_setup(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        root = Path(__file__).resolve().parents[1]
        production = (root / 'src/screens/UScreenName.pas').read_text()
        geometry = 'function TScreenName.DifficultySegmentRect' + production.split(
            'function TScreenName.DifficultySegmentRect', 1)[1].split(
            'function TScreenName.ParseMouse', 1)[0]
        method = production.split(
            'function TScreenName.ParseMouse(', 1)[1]
        method = 'function TScreenName.ParseMouse(' + method.split(
            '  if (BtnDown) then', 1)[0] + 'end;\n'
        harness = r'''program CardMouse;
{$mode Delphi}
uses SysUtils, Math;
type
 TPlayerSlotRect = record X,Y,W,H: integer; end;
 TMouseOverRect = record X,Y,W,H: single; end;
 TText = record Text: string; end;
 TButton = record Selected: boolean; Text: array[0..0] of TText; end;
 TSlide = class procedure SetSelectOpt(Value: integer); end;
 TBase = class
  Interaction: integer;
  function ParseMouse(MouseButton: integer; BtnDown: boolean; X,Y: integer): boolean; virtual;
 end;
 TScreenName = class(TBase)
  PlayerIndex, AvatarTarget, AvatarCurrent, LevelIndex: integer;
  SelectedPlayerCount: integer;
  PlayerNames: array[0..1] of string;
  PlayerAvatars, PlayerLevel: array[0..1] of integer;
  Button: array[0..0] of TButton;
  SelectsS: array[0..0] of TSlide;
  function InteractAt(X,Y: integer): integer;
  function CardRect(I: integer): TPlayerSlotRect;
  function DifficultySegmentRect(PlayerID, Segment: integer): TMouseOverRect;
  procedure RefreshProfile;
  function ParseMouse(MouseButton: integer; BtnDown: boolean; X,Y: integer): boolean; override;
 end;
const SDL_BUTTON_LEFT=1; PlayerName=0; PlayerNameIID=2;
 PlayerAvatarIID=3; PlayerColorIID=4; PlayerSelectLevelIID=5;
 PlayerSelectVoiceIID=6; PlayerSelectLevel=0;
var
 Theme: record Name: record
  Cards: record Enabled,LevelSegments,EditOutside:boolean; Columns,Rows:integer;
   Panel: record W,H:real; end; end;
  SelectPlayerLevel: record X,Y:real; end;
 end; end;
 ScreenW,ScreenH,Screens,RenderW,RenderH: integer;
 Hit,Calls,LastX,LastY: integer; S:TScreenName;
procedure SetTextInput(Value:boolean); begin end;
procedure TSlide.SetSelectOpt(Value:integer); begin end;
function TBase.ParseMouse(MouseButton:integer; BtnDown:boolean; X,Y:integer):boolean;
begin Inc(Calls);LastX:=X;LastY:=Y;Result:=true;end;
function TScreenName.InteractAt(X,Y:integer):integer;
begin Result:=Hit;end;
function TScreenName.CardRect(I:integer):TPlayerSlotRect;
begin Result.X:=I*100;Result.Y:=0;Result.W:=100;Result.H:=100;end;
procedure TScreenName.RefreshProfile; begin end;
''' + geometry + method + r'''
procedure Check(Value:boolean;const Msg:string);
begin if not Value then raise Exception.Create(Msg);end;
begin
 ScreenW:=1600;ScreenH:=1200;Screens:=1;RenderW:=800;RenderH:=600;
 Theme.Name.Cards.Enabled:=true;Theme.Name.Cards.Columns:=2;
 Theme.Name.Cards.Rows:=1;Theme.Name.Cards.Panel.H:=100;Theme.Name.Cards.Panel.W:=100;
 Theme.Name.SelectPlayerLevel.X:=10;
 S:=TScreenName.Create;S.SelectedPlayerCount:=2;S.SelectsS[0]:=TSlide.Create;
 try
  Hit:=PlayerAvatarIID;S.ParseMouse(1,true,40,40);
  Check((Calls=0) and (S.Interaction=PlayerAvatarIID),'avatar click submitted setup');
  Hit:=PlayerNameIID;S.ParseMouse(1,true,40,40);
  Check((Calls=0) and (S.Interaction=PlayerNameIID),'name click submitted setup');
  S.ParseMouse(1,true,900,700);
  Check(Calls=0,'external name editor submitted setup');
  Hit:=-1;S.ParseMouse(1,true,240,40);
  Check((Calls=0) and (S.PlayerIndex=1),'other card was not selected safely');
  Hit:=PlayerSelectVoiceIID;S.ParseMouse(1,true,240,40);
  Check((Calls=1) and (LastX=240) and (LastY=40),'slide lost native coordinates');
  Theme.Name.Cards.LevelSegments:=true;Theme.Name.SelectPlayerLevel.Y:=50;
  Hit:=PlayerSelectLevelIID;S.ParseMouse(1,true,350,110);
  Check((Calls=1) and (S.LevelIndex=2),'difficulty segment delegated twice');
  Theme.Name.Cards.EditOutside:=true;
  S.ParseMouse(1,true,40,110);
  Check((Calls=1) and (S.LevelIndex=0),'external difficulty segment submitted setup');
  Theme.Name.Cards.Enabled:=false;Hit:=PlayerNameIID;
  S.ParseMouse(1,true,40,40);Check(Calls=2,'legacy click dispatch changed');
 finally S.SelectsS[0].Free;S.Free;end;
 WriteLn('PASS: card editors, external editor, card selection, slide coordinates, difficulty and legacy dispatch');
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'card_mouse.pas'
            source.write_text(harness)
            flags = ['-Px86_64'] if os.name == 'nt' else []
            result = subprocess.run([compiler, '-B', '-Mdelphi', '-Ciro', *flags,
                '-FU' + directory, '-FE' + directory, str(source)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(source.with_suffix('.exe' if os.name == 'nt' else ''))],
                           check=True, timeout=5)
