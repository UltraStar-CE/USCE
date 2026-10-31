{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenPartyWin.pas $
 * $Id: UScreenPartyWin.pas 2246 2010-04-18 13:43:36Z tobigun $
 *}

unit UScreenPartyTournamentRounds;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UDisplay,
  UDocumentUI,
  UIni,
  UMenu,
  UMusic,
  UPartyTournament,
  UScreenPartyTournamentWin,
  UScreenSingController,
  UThemes,
  sdl2,
  SysUtils,
  UText;

type

  Line = record
    X: real;
    Y: real;
    H: real;
    W: real;
  end;

  TScreenPartyTournamentRounds = class(TMenu)
    private
      DocumentUI: TDocumentUI;
      DocumentSelection: integer;
      function ParticipantVisible(Id: integer): boolean;
      function ParticipantName(Id: integer): UTF8String;
      procedure PrepareMatch;
      procedure SyncDocument;
    public

      TextNamePlayer: array[0..1, 0..7] of cardinal;
      NextPlayersMark: array [0..15] of cardinal;
      TextWinner: cardinal;

      ButtonPlayer1: cardinal;
      ButtonPlayer2: cardinal;

      TextColorPlayerR: array[0..1, 0..7] of real;
      TextColorPlayerG: array[0..1, 0..7] of real;
      TextColorPlayerB: array[0..1, 0..7] of real;

      R1, G1, B1: real;
      R2, G2, B2: real;

      DR1, DG1, DB1: real;
      DR2, DG2, DB2: real;

      XResult: integer;
      YResult: integer;
      SizeResult: integer;
      FontResult: integer;
      ColorResult: TRGB;

    //private
      Lines: array [0..3, 0..15, 0..1] of Line;

      Num: array[0..1]of integer;

      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      function Draw: boolean; override;

      procedure DrawLine(X, Y, W, H: real);
      procedure DrawLinePlayer1(X, Y, W, H: real);
      procedure DrawLinePlayer2(X, Y, W, H: real);

      procedure DrawGrid();
      procedure DrawGridBlock1();
      procedure DrawGridBlock2();

      function EliminatedPlayer(Id: integer): boolean;
      function ExistPlayers(Phase: integer): boolean;

      function GetPlayers8Final(): NextPlayers;
      function GetPlayers4Final(): NextPlayers;
      function GetPlayers2Final(): NextPlayers;
      function GetPlayersFinal(): NextPlayers;

      procedure PlayerColorButton(K: integer; Interact: integer);
      function NoRepeatColors(ColorP: integer; Interaction: integer; Pos: integer):integer;
  end;

const
  ID='ID_038';   //for help system

implementation

uses
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UMain,
  UMenuText,
  URenderer,
  UUnicodeUtils;



procedure TScreenPartyTournamentRounds.PrepareMatch;
begin
  if (PartyTournament.Phase = 0) then
    PartyTournament.Next := GetPlayers8Final();

  if (PartyTournament.Next.Player1 = PartyTournament.Next.Player2) and (ExistPlayers(PartyTournament.Phase)) then
  begin
    PartyTournament.LastPlayer := -1;
    PartyTournament.Next := GetPlayers8Final();
  end;

  if (PartyTournament.Phase = 0) and (PartyTournament.Next.Player1 = PartyTournament.Next.Player2) then
    PartyTournament.Phase := 1;

  if (PartyTournament.Phase = 1) then
    PartyTournament.Next := GetPlayers4Final();

  if (PartyTournament.Next.Player1 = PartyTournament.Next.Player2) and (ExistPlayers(PartyTournament.Phase)) then
  begin
    PartyTournament.LastPlayer := -1;
    PartyTournament.Next := GetPlayers4Final();
  end;

  if (PartyTournament.Phase = 1) and (PartyTournament.Next.Player1 = PartyTournament.Next.Player2) then
    PartyTournament.Phase := 2;

  if (PartyTournament.Phase = 2) then
    PartyTournament.Next := GetPlayers2Final();

  if (PartyTournament.Next.Player1 = PartyTournament.Next.Player2) and (ExistPlayers(PartyTournament.Phase)) then
  begin
    PartyTournament.LastPlayer := -1;
    PartyTournament.Next := GetPlayers2Final();
  end;

  if (PartyTournament.Phase = 2) and (PartyTournament.Next.Player1 = PartyTournament.Next.Player2) then
    PartyTournament.Phase := 3;

  if (PartyTournament.Phase = 3) then
    PartyTournament.Next := GetPlayersFinal();

end;

function TScreenPartyTournamentRounds.ParticipantVisible(Id: integer): boolean;
const MinimumPlayers: array[0..15] of integer = (2,9,13,5,3,11,15,7,2,10,14,6,4,12,16,8);
begin
  Result := (Id >= 0) and (Id <= 15);
  if not Result then Exit;
  if DocumentUI = nil then Result := Button[Id].Visible
  else Result := PartyTournament.PlayersCount >= MinimumPlayers[Id];
end;

function TScreenPartyTournamentRounds.ParticipantName(Id: integer): UTF8String;
var I, N: integer;
begin
  Result := '';
  if not ParticipantVisible(Id) then Exit;
  N := 0;
  for I := 0 to Id - 1 do if ParticipantVisible(I) then Inc(N);
  Result := ScreenPartyTournamentPlayer.PlayersName[N];
end;

procedure TScreenPartyTournamentRounds.SyncDocument;
var I, Side, Phase, Group, Count, Index, P, ActivePlayer: integer;
    Prefix, ColorText, Mark: UTF8String; Col: TRGB;
  function ColorString(const C: TRGB): UTF8String;
  begin
    Result := '#' + IntToHex(Round(C.R * 255), 2) +
      IntToHex(Round(C.G * 255), 2) + IntToHex(Round(C.B * 255), 2);
  end;
begin
  DocumentUI.SetModel('tournament.winner', PartyTournament.Winner);
  DocumentUI.SetModel('tournament.phase', IntToStr(PartyTournament.Phase), 1);
  DocumentUI.SetModel('tournament.finished', IntToStr(Ord(PartyTournament.TournamentFinish)), 2);
  DocumentUI.SetArray('tournament.players', 16);
  for I := 0 to 15 do
  begin
    Prefix := 'tournament.players[' + IntToStr(I) + '].';
    DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
    DocumentUI.SetModel(Prefix + 'side', IntToStr(I div 8), 1);
    DocumentUI.SetModel(Prefix + 'slot', IntToStr(I mod 8), 1);
    DocumentUI.SetModel(Prefix + 'name', ParticipantName(I));
    DocumentUI.SetModel(Prefix + 'visible', IntToStr(Ord(ParticipantVisible(I))), 2);
    DocumentUI.SetModel(Prefix + 'eliminated', IntToStr(Ord(EliminatedPlayer(I))), 2);
    Mark := '';
    ActivePlayer := -1;
    if I = PartyTournament.Next.Player1 then begin Mark := 'P1'; ActivePlayer := 0; end;
    if I = PartyTournament.Next.Player2 then begin Mark := 'P2'; ActivePlayer := 1; end;
    DocumentUI.SetModel(Prefix + 'mark', Mark);
    DocumentUI.SetModel(Prefix + 'active', IntToStr(Ord((ActivePlayer >= 0) and not PartyTournament.TournamentFinish)), 2);
    DocumentUI.SetModel(Prefix + 'selected', IntToStr(Ord(I = DocumentSelection)), 2);
    ColorText := '';
    if ActivePlayer >= 0 then
    begin
      if I = DocumentSelection then Col := GetPlayerColor(Num[ActivePlayer])
      else Col := GetPlayerLightColor(Num[ActivePlayer]);
      ColorText := ColorString(Col);
    end;
    DocumentUI.SetModel(Prefix + 'color', ColorText);
  end;
  DocumentUI.SetArray('tournament.nodes', 30);
  Index := 0;
  for Side := 0 to 1 do
    for Phase := 0 to 3 do
    begin
      Count := 8 shr Phase;
      for Group := 0 to Count - 1 do
      begin
        Prefix := 'tournament.nodes[' + IntToStr(Index) + '].';
        DocumentUI.SetModel(Prefix + 'side', IntToStr(Side), 1);
        DocumentUI.SetModel(Prefix + 'phase', IntToStr(Phase), 1);
        DocumentUI.SetModel(Prefix + 'group', IntToStr(Group), 1);
        ColorText := '';
        for P := 0 to 1 do
        begin
          if P = 0 then I := PartyTournament.Next.Player1 else I := PartyTournament.Next.Player2;
          if (Phase <= PartyTournament.Phase) and (I div 8 = Side) and
             ((I mod 8) shr Phase = Group) then
          begin
            if I = DocumentSelection then Col := GetPlayerColor(Num[P])
            else Col := GetPlayerLightColor(Num[P]);
            ColorText := ColorString(Col);
          end;
        end;
        DocumentUI.SetModel(Prefix + 'color', ColorText);
        DocumentUI.SetModel(Prefix + 'active', IntToStr(Ord(ColorText <> '')), 2);
        Inc(Index);
      end;
    end;
  DocumentUI.SetArray('tournament.scores', 48);
  for Phase := 0 to 2 do
    for I := 0 to 15 do
    begin
      Prefix := 'tournament.scores[' + IntToStr(Phase * 16 + I) + '].';
      DocumentUI.SetModel(Prefix + 'phase', IntToStr(Phase), 1);
      DocumentUI.SetModel(Prefix + 'side', IntToStr(I div 8), 1);
      DocumentUI.SetModel(Prefix + 'group', IntToStr((I mod 8) shr Phase), 1);
      DocumentUI.SetModel(Prefix + 'value', PartyTournament.ResultPlayer[Phase, I].Text);
    end;
end;

destructor TScreenPartyTournamentRounds.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenPartyTournamentRounds.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenPartyTournamentRounds.DrawFG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(false, true) else Result := inherited;
end;

function TScreenPartyTournamentRounds.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action, Target: UTF8String; Selected: integer;
begin
  if DocumentUI = nil then Exit(inherited);
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then
    Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
  else DocumentUI.Mouse(X, Y);
  Action := DocumentUI.TakeAction;
  Target := DocumentUI.ActionTarget;
  if Action = 'tournament.continue' then Exit(ParseInput(SDLK_RETURN, 0, true));
  if Action = uiNavigationBack then Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if (Action = 'tournament.select-player') and TryStrToInt(Target, Selected) and
     not PartyTournament.TournamentFinish then
    if (Selected = PartyTournament.Next.Player1) or (Selected = PartyTournament.Next.Player2) then
      begin
        DocumentSelection := Selected;
        SyncDocument;
      end;
  Result := true;
end;

procedure OnFinish(Value: boolean; Data: Pointer);
begin
  if (Value) then
  begin
    AudioPlayback.PlaySound(SoundLib.Start);
    Display.FadeTo(@ScreenMain);
  end;
end;

function TScreenPartyTournamentRounds.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
var
  SDL_ModState: word;
  Player: integer;
begin
  Result := true;
  if (PressedDown) then
  begin // Key Down
    // check normal keys
    case PressedKey of
      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;

    SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
    + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT);

    if (DocumentUI <> nil) and not PartyTournament.TournamentFinish and
       ((PressedKey = SDLK_UP) or (PressedKey = SDLK_DOWN) or
        (PressedKey = SDLK_LEFT) or (PressedKey = SDLK_RIGHT)) then
    begin
      if (SDL_ModState = KMOD_LCTRL) and
         ((PressedKey = SDLK_UP) or (PressedKey = SDLK_DOWN)) then
      begin
        if DocumentSelection = PartyTournament.Next.Player1 then Player := 0 else Player := 1;
        if PressedKey = SDLK_UP then Inc(Num[Player]) else Dec(Num[Player]);
        if PressedKey = SDLK_UP then Num[Player] := NoRepeatColors(Num[Player], Player, 1)
        else Num[Player] := NoRepeatColors(Num[Player], Player, -1);
        PlayerColorButton(Num[Player], DocumentSelection);
      end
      else if DocumentSelection = PartyTournament.Next.Player1 then
        DocumentSelection := PartyTournament.Next.Player2
      else DocumentSelection := PartyTournament.Next.Player1;
      SyncDocument;
      DocumentUI.Focus('player-' + IntToStr(DocumentSelection));
      Exit;
    end;

    // check special keys
    case PressedKey of
      SDLK_BACKSPACE,
      SDLK_ESCAPE:
        begin
          ScreenPopupCheck.ShowPopup('MSG_END_PARTY', OnFinish, nil);
        end;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_RETURN :
        begin

          if (PartyTournament.TournamentFinish) then
          begin
            OnFinish(true, nil);
          end
          else
          begin

            Ini.SingColor[0] := Num[0];
            Ini.SingColor[1] := Num[1];

            LoadPlayersColors;

            freeandnil(ScreenSing);
            ScreenSing  := TScreenSingController.Create;

            AudioPlayback.PlaySound(SoundLib.Start);
            FadeTo(@ScreenSong);

          end;
        end;

      // Up and Down could be done at the same time,
      // but I don't want to declare variables inside
      // functions like this one, called so many times
      SDLK_DOWN:
      begin
       if not (PartyTournament.TournamentFinish) then
       begin
        if (SDL_ModState = KMOD_LCTRL) then
         begin
           if (Interaction = PartyTournament.Next.Player1) then
             Player := 0
           else
             Player := 1;

           Num[Player] := Num[Player] - 1;
           Num[Player] := NoRepeatColors(Num[Player], Player, -1);
           PlayerColorButton(Num[Player], Interaction);
         end
         else
           InteractNext;
       end;
      end;
      SDLK_UP:
      begin
       if not (PartyTournament.TournamentFinish) then
       begin
         if (SDL_ModState = KMOD_LCTRL) then
         begin
           if (Interaction = PartyTournament.Next.Player1) then
             Player := 0
           else
             Player := 1;

           Num[Player] := Num[Player] + 1;
           Num[Player] := NoRepeatColors(Num[Player], Player, 1);
           PlayerColorButton(Num[Player], Interaction);
         end
         else
           InteractPrev;
       end;
      end;
      SDLK_RIGHT: if not (PartyTournament.TournamentFinish) then InteractNext;
      SDLK_LEFT:  if not (PartyTournament.TournamentFinish) then InteractPrev;

    end;
  end;
end;

function TScreenPartyTournamentRounds.NoRepeatColors(ColorP:integer; Interaction:integer; Pos:integer):integer;
var
  Z:integer;
begin

  if (ColorP >= 10) then
    ColorP := NoRepeatColors(1, Interaction, Pos);

  if (ColorP <= 0) then
    ColorP := NoRepeatColors(9, Interaction, Pos);

  for Z := 0 to 1 do
  begin
    if Z <> Interaction then
    begin
     if (Num[Z] = ColorP) then
       ColorP := NoRepeatColors(ColorP + Pos, Interaction, Pos)
    end;
  end;

  Result := ColorP;

end;

procedure TScreenPartyTournamentRounds.PlayerColorButton(K: integer; Interact: integer);
var
  Col, DesCol: TRGB;
begin

  Col := GetPlayerColor(K);

  if DocumentUI = nil then
  begin
  Button[Interact].SelectColR:= Col.R;
  Button[Interact].SelectColG:= Col.G;
  Button[Interact].SelectColB:= Col.B;

  end;

  DesCol := GetPlayerLightColor(K);

  if DocumentUI = nil then
  begin
  Button[Interact].DeselectColR:= DesCol.R;
  Button[Interact].DeselectColG:= DesCol.G;
  Button[Interact].DeselectColB:= DesCol.B;

  end;

  If (Interact = PartyTournament.Next.Player1) then
  begin
    R1 := Col.R;
    G1 := Col.G;
    B1 := Col.B;

    DR1 := DesCol.R;
    DG1 := DesCol.G;
    DB1 := DesCol.B;

    Ini.SingColor[0] := K;
  end
  else
  begin
    R2 := Col.R;
    G2 := Col.G;
    B2 := Col.B;

    DR2 := DesCol.R;
    DG2 := DesCol.G;
    DB2 := DesCol.B;

    Ini.SingColor[1] := K;
  end;

  if DocumentUI = nil then Interaction := Interact
  else DocumentSelection := Interact;

end;

constructor TScreenPartyTournamentRounds.Create;
var
  I, J: integer;
  Col: TRGB;
  R, G, B: real;
  X, Y: integer;
begin
  inherited Create;

  Num[0] := 1;
  Num[1] := 2;
  DocumentUI := TDocumentUI.Open('tournament-rounds');
  if DocumentUI <> nil then
  begin
    DocumentSelection := -1;
    Exit;
  end;

  LoadFromTheme(Theme.PartyTournamentRounds);

  X := Theme.PartyTournamentRounds.NextPlayers.X;
  Y := Theme.PartyTournamentRounds.NextPlayers.Y;

  for I := 0 to 1 do
  begin
    for J := 0 to 7 do
    begin
      TextNamePlayer[I, J] := AddButton (Theme.PartyTournamentRounds.TextNamePlayer[I, J]);
      TextColorPlayerR[I, J] := Theme.PartyTournamentRounds.TextNamePlayer[I, J].ColR;
      TextColorPlayerG[I, J] := Theme.PartyTournamentRounds.TextNamePlayer[I, J].ColG;
      TextColorPlayerB[I, J] := Theme.PartyTournamentRounds.TextNamePlayer[I, J].ColB;

      if (I = 0) then
        Theme.PartyTournamentRounds.NextPlayers.X := X +
                                                   Theme.PartyTournamentRounds.TextNamePlayer[I, J].X +
                                                   Theme.PartyTournamentRounds.TextNamePlayer[I, J].W
      else
      begin
        Theme.PartyTournamentRounds.NextPlayers.X := Theme.PartyTournamentRounds.TextNamePlayer[I, J].X - X;
        Theme.PartyTournamentRounds.NextPlayers.Align := 2;
      end;

      Theme.PartyTournamentRounds.NextPlayers.Y := Y +
                                                   Theme.PartyTournamentRounds.TextNamePlayer[I, J].Y;

      NextPlayersMark[J + I * 8] := AddText (Theme.PartyTournamentRounds.NextPlayers);
    end;
  end;

  TextWinner := AddText(Theme.PartyTournamentRounds.TextWinner);

  Num[0] := 1;
  Num[1] := 2;

  Col := GetPlayerColor(1);

  R1 := Col.R;
  G1 := Col.G;
  B1 := Col.B;

  Col := GetPlayerLightColor(1);

  DR1 := Col.R;
  DG1 := Col.G;
  DB1 := Col.B;

  Col := GetPlayerColor(2);

  R2 := Col.R;
  G2 := Col.G;
  B2 := Col.B;

  Col := GetPlayerLightColor(2);

  DR2 := Col.R;
  DG2 := Col.G;
  DB2 := Col.B;

  XResult :=    Theme.PartyTournamentRounds.TextResult.X;
  YResult :=    Theme.PartyTournamentRounds.TextResult.Y;
  FontResult := Theme.PartyTournamentRounds.TextResult.Font;
  SizeResult := Theme.PartyTournamentRounds.TextResult.Size;

  LoadColor(R, G, B, Theme.PartyTournamentRounds.TextResult.Color);

  ColorResult.R := R;
  ColorResult.G := G;
  ColorResult.B := B;

end;

procedure TScreenPartyTournamentRounds.OnShow;
var
  I, J, Count: integer;
  CountPlayer: integer;
begin
  if DocumentUI = nil then inherited;

  if DocumentUI <> nil then
  begin
    Help.SetHelpID(ID);
    PrepareMatch;
    PartyTournament.Next.NamePlayer1 := ParticipantName(PartyTournament.Next.Player1);
    PartyTournament.Next.NamePlayer2 := ParticipantName(PartyTournament.Next.Player2);
    DocumentSelection := PartyTournament.Next.Player1;
    PlayerColorButton(Num[1], PartyTournament.Next.Player2);
    PlayerColorButton(Num[0], PartyTournament.Next.Player1);
    if PartyTournament.TournamentFinish then
      ScreenPopupInfo.ShowPopup(Format(Language.Translate('PARTY_MODE_TOURNAMENT_CHAMPION'), [PartyTournament.Winner]));
    SyncDocument;
    DocumentUI.Focus('player-' + IntToStr(DocumentSelection));
    Exit;
  end;

  if not Help.SetHelpID(ID) then
    Log.LogError('No Entry for Help-ID ' + ID + ' (ScreenPartyTournamentRounds)');

  CountPlayer := PartyTournament.PlayersCount;

  for I := 0 to 1 do
  begin
    for J := 0 to 7 do
    begin
      Button[TextNamePlayer[I, J]].Visible := false;
      Button[TextNamePlayer[I, J]].Selectable := false;
      Button[TextNamePlayer[I, J]].Texture.Alpha := 1;

      Button[TextNamePlayer[I, J]].DeselectColR := TextColorPlayerR[I, J];
      Button[TextNamePlayer[I, J]].DeselectColG := TextColorPlayerG[I, J];
      Button[TextNamePlayer[I, J]].DeselectColB := TextColorPlayerB[I, J];

      Button[TextNamePlayer[I, J]].SetSelect(false);

      Text[NextPlayersMark[J + I * 8]].Text := '';
    end;
  end;

  if (CountPlayer >= 2) then
  begin
    Button[TextNamePlayer[0, 0]].Visible := true;
    Button[TextNamePlayer[1, 0]].Visible := true;
  end;

  if (CountPlayer >= 3) then
    Button[TextNamePlayer[0, 4]].Visible := true;

  if (CountPlayer >= 4) then
    Button[TextNamePlayer[1, 4]].Visible := true;

  if (CountPlayer >= 5) then
    Button[TextNamePlayer[0, 3]].Visible := true;

  if (CountPlayer >= 6) then
    Button[TextNamePlayer[1, 3]].Visible := true;

  if (CountPlayer >= 7) then
    Button[TextNamePlayer[0, 7]].Visible := true;

  if (CountPlayer >= 8) then
    Button[TextNamePlayer[1, 7]].Visible := true;

  if (CountPlayer >= 9) then
    Button[TextNamePlayer[0, 1]].Visible := true;

  if (CountPlayer >= 10) then
    Button[TextNamePlayer[1, 1]].Visible := true;

  if (CountPlayer >= 11) then
    Button[TextNamePlayer[0, 5]].Visible := true;

  if (CountPlayer >= 12) then
    Button[TextNamePlayer[1, 5]].Visible := true;

  if (CountPlayer >= 13) then
    Button[TextNamePlayer[0, 2]].Visible := true;

  if (CountPlayer >= 14) then
    Button[TextNamePlayer[1, 2]].Visible := true;

  if (CountPlayer >= 15) then
    Button[TextNamePlayer[0, 6]].Visible := true;

  if (CountPlayer = 16) then
    Button[TextNamePlayer[1, 6]].Visible := true;

  Count := 0;

  PrepareMatch;

  for I := 0 to 15 do
  begin
    Button[I].SetSelect(false);

    if (Button[I].Visible) then
    begin

      //Player Name
      Button[I].Text[0].Text := ScreenPartyTournamentPlayer.PlayersName[Count];

      if (PartyTournament.Next.Player1 = I) then
      begin

        PartyTournament.Next.NamePlayer1 := Button[I].Text[0].Text;

        if not(PartyTournament.TournamentFinish) then
          Button[I].Selectable := true;

        Text[NextPlayersMark[I]].Text := 'P1';

        Button[I].SelectColR := R1;
        Button[I].SelectColG := G1;
        Button[I].SelectColB := B1;

        Button[I].DeselectColR := DR1;
        Button[I].DeselectColG := DG1;
        Button[I].DeselectColB := DB1;

        Button[I].SetSelect(true);
      end;

      if (PartyTournament.Next.Player2 = I) then
      begin

        PartyTournament.Next.NamePlayer2 := Button[I].Text[0].Text;

        if not(PartyTournament.TournamentFinish) then
          Button[I].Selectable := true;

        Text[NextPlayersMark[I]].Text := 'P2';

        Button[I].SelectColR := R2;
        Button[I].SelectColG := G2;
        Button[I].SelectColB := B2;

        Button[I].DeselectColR := DR2;
        Button[I].DeselectColG := DG2;
        Button[I].DeselectColB := DB2;

        // do better
        Button[I].SetSelect(true);
        Button[I].SetSelect(false);
      end;

      Count := Count + 1;

    end;

  end;

  // eliminated players
  for I := 0 to High(PartyTournament.EliminatedPlayers) do
  begin
    Button[PartyTournament.EliminatedPlayers[I]].Texture.Alpha := 0.1;
    Button[PartyTournament.EliminatedPlayers[I]].SetSelect(false);
  end;

  if (PartyTournament.TournamentFinish = false) then
  begin
    Interaction := PartyTournament.Next.Player1;
  end
  else
  begin
    Button[PartyTournament.Next.Player1].Selectable := false;
    Button[PartyTournament.Next.Player2].Selectable := false;

    Button[PartyTournament.Next.Player1].SetSelect(false);
    Button[PartyTournament.Next.Player2].SetSelect(false);

    ScreenPopupInfo.ShowPopup(Format(Language.Translate('PARTY_MODE_TOURNAMENT_CHAMPION'), [PartyTournament.Winner]))
  end;

  Text[TextWinner].Text := PartyTournament.Winner;

end;

function TScreenPartyTournamentRounds.EliminatedPlayer(Id: integer): boolean;
var
  I: integer;
  Find: boolean;
begin

  Find := false;

  for I := 0 to High(PartyTournament.EliminatedPlayers) do
  begin
    if (PartyTournament.EliminatedPlayers[I] = Id) then
      Find := true;
  end;

  Result := Find;
end;

function TScreenPartyTournamentRounds.ExistPlayers(Phase: integer): boolean;
var
  I, CountV, CountE, Total, Valor: integer;
begin
  CountV := 0;
  Valor := 16;

  for I := 0 to 15 do
  begin
    if not(ParticipantVisible(I)) then
        CountV := CountV + 1;
  end;

  CountE := Length(PartyTournament.EliminatedPlayers);
  Total := CountV + CountE;

  case Phase of
    0: Valor := 8;
    1: Valor := 12;
    2: Valor := 14;
  end;

  if (Total < Valor) then
    Result := true
  else
    Result := false;

end;

function TScreenPartyTournamentRounds.GetPlayers8Final(): NextPlayers;
var
  Count: integer;
  _Next: NextPlayers;
  Find: boolean;
begin
  _Next.Player1 := 0;
  _Next.Player2 := 0;

  Count := 0;
  Find := false;

  while (Count < 15) and (Find = false) do
  begin

    if (Count > PartyTournament.LastPlayer) and (ParticipantVisible(Count)) and (ParticipantVisible(Count + 1))
      and not(EliminatedPlayer(Count)) and not(EliminatedPlayer(Count + 1)) then
    begin
      _Next.Player1 := Count;
      _Next.Player2 := Count + 1;

      Find:= true;
    end;

    Count := Count + 2;
  end;

  Result := _Next;
end;

function TScreenPartyTournamentRounds.GetPlayers4Final(): NextPlayers;
var
  _Next: NextPlayers;
  Find: boolean;
begin
  _Next.Player1 := -1;
  _Next.Player2 := -1;

  Find := false;

  if (PartyTournament.LastPlayer < 1) then
  begin
    if (ParticipantVisible(0)) and not EliminatedPlayer(0) then
      _Next.Player1 := 0;

    if (ParticipantVisible(1)) and not EliminatedPlayer(1) then
      _Next.Player1 := 1;
  end;

  if (PartyTournament.LastPlayer < 3) then
  begin
    if (ParticipantVisible(2)) and not EliminatedPlayer(2) then
      _Next.Player2 := 2;

    if (ParticipantVisible(3)) and not EliminatedPlayer(3) then
      _Next.Player2 := 3;
  end;

  if (_Next.Player1 <> -1) and (_Next.Player2 <> -1) then
    Find := true;

  if not Find then
  begin
    _Next.Player1 := -1;
    _Next.Player2 := -1;

    if (PartyTournament.LastPlayer < 5) then
    begin
      if (ParticipantVisible(4)) and not EliminatedPlayer(4) then
        _Next.Player1 := 4;

      if (ParticipantVisible(5)) and not EliminatedPlayer(5) then
        _Next.Player1 := 5;
    end;

    if (PartyTournament.LastPlayer < 7) then
    begin
      if (ParticipantVisible(6)) and not EliminatedPlayer(6) then
        _Next.Player2 := 6;

      if (ParticipantVisible(7)) and not EliminatedPlayer(7) then
        _Next.Player2 := 7;
    end;

    if (_Next.Player1 <> -1) and (_Next.Player2 <> -1) then
        Find := true;
  end;

  if not Find then
  begin
    _Next.Player1 := -1;
    _Next.Player2 := -1;

    if (PartyTournament.LastPlayer < 9) then
    begin
      if (ParticipantVisible(8)) and not EliminatedPlayer(8) then
        _Next.Player1 := 8;

      if (ParticipantVisible(9)) and not EliminatedPlayer(9) then
        _Next.Player1 := 9;
    end;

    if (PartyTournament.LastPlayer < 11) then
    begin
      if (ParticipantVisible(10)) and not EliminatedPlayer(10) then
        _Next.Player2 := 10;

      if (ParticipantVisible(11)) and not EliminatedPlayer(11) then
        _Next.Player2 := 11;
    end;

    if (_Next.Player1 <> -1) and (_Next.Player2 <> -1) then
        Find := true;
  end;

  if not Find then
  begin
    _Next.Player1 := -1;
    _Next.Player2 := -1;

    if (PartyTournament.LastPlayer < 13) then
    begin
      if (ParticipantVisible(12)) and not EliminatedPlayer(12) then
        _Next.Player1 := 12;

      if (ParticipantVisible(13)) and not EliminatedPlayer(13) then
        _Next.Player1 := 13;
    end;

    if (PartyTournament.LastPlayer < 15) then
    begin
      if (ParticipantVisible(14)) and not EliminatedPlayer(14) then
        _Next.Player2 := 14;

      if (ParticipantVisible(15)) and not EliminatedPlayer(15) then
        _Next.Player2 := 15;
    end;

    if (_Next.Player1 <> -1) and (_Next.Player2 <> -1) then
        Find := true;
  end;

  if not Find then
  begin
    _Next.Player1 := 0;
    _Next.Player2 := 0;
  end;

  Result := _Next;
end;

function TScreenPartyTournamentRounds.GetPlayers2Final(): NextPlayers;
var
  _Next: NextPlayers;
  Find: boolean;
begin

  _Next.Player1 := -1;
  _Next.Player2 := -1;

  Find := false;

  if (PartyTournament.LastPlayer < 3) then
  begin
    if (ParticipantVisible(0)) and not EliminatedPlayer(0) then
      _Next.Player1 := 0;

    if (ParticipantVisible(1)) and not EliminatedPlayer(1) then
      _Next.Player1 := 1;

    if (ParticipantVisible(2)) and not EliminatedPlayer(2) then
      _Next.Player1 := 2;

    if (ParticipantVisible(3)) and not EliminatedPlayer(3) then
      _Next.Player1 := 3;
  end;

  if (PartyTournament.LastPlayer < 7) then
  begin
    if (ParticipantVisible(4)) and not EliminatedPlayer(4)  then
      _Next.Player2 := 4;

    if (ParticipantVisible(5)) and not EliminatedPlayer(5) then
      _Next.Player2 := 5;

    if (ParticipantVisible(6)) and not EliminatedPlayer(6) then
      _Next.Player2 := 6;

    if (ParticipantVisible(7)) and not EliminatedPlayer(7) then
      _Next.Player2 := 7;
  end;

  if (_Next.Player1 <> -1) and (_Next.Player2 <> -1) then
      Find := true;

  if not Find then
  begin
    _Next.Player1 := -1;
    _Next.Player2 := -1;

    if (PartyTournament.LastPlayer < 11) then
    begin
      if (ParticipantVisible(8)) and not EliminatedPlayer(8) then
        _Next.Player1 := 8;

      if (ParticipantVisible(9)) and not EliminatedPlayer(9) then
        _Next.Player1 := 9;

      if (ParticipantVisible(10)) and not EliminatedPlayer(10) then
        _Next.Player1 := 10;

      if (ParticipantVisible(11)) and not EliminatedPlayer(11) then
        _Next.Player1 := 11;
    end;

    if (PartyTournament.LastPlayer < 15) then
    begin
      if (ParticipantVisible(12)) and not EliminatedPlayer(12) then
        _Next.Player2 := 12;

      if (ParticipantVisible(13)) and not EliminatedPlayer(13) then
        _Next.Player2 := 13;

      if (ParticipantVisible(14)) and not EliminatedPlayer(14) then
        _Next.Player2 := 14;

      if (ParticipantVisible(15)) and not EliminatedPlayer(15) then
        _Next.Player2 := 15;
    end;

    if (_Next.Player1 <> -1) and (_Next.Player2 <> -1) then
        Find := true;
  end;

  if not Find then
  begin
    _Next.Player1 := 0;
    _Next.Player2 := 0;
  end;

  Result := _Next;

end;

function TScreenPartyTournamentRounds.GetPlayersFinal: NextPlayers;
var
  _Next: NextPlayers;
begin

  _Next.Player1 := -1;
  _Next.Player2 := -1;

  if (ParticipantVisible(0)) and not EliminatedPlayer(0) then
      _Next.Player1 := 0;

  if (ParticipantVisible(1)) and not EliminatedPlayer(1) then
      _Next.Player1 := 1;

  if (ParticipantVisible(2)) and not EliminatedPlayer(2) then
      _Next.Player1 := 2;

  if (ParticipantVisible(3)) and not EliminatedPlayer(3) then
      _Next.Player1 := 3;

  if (ParticipantVisible(4)) and not EliminatedPlayer(4) then
      _Next.Player1 := 4;

  if (ParticipantVisible(5)) and not EliminatedPlayer(5) then
      _Next.Player1 := 5;

  if (ParticipantVisible(6)) and not EliminatedPlayer(6) then
      _Next.Player1 := 6;

  if (ParticipantVisible(7)) and not EliminatedPlayer(7) then
      _Next.Player1 := 7;

  if (ParticipantVisible(8)) and not EliminatedPlayer(8) then
      _Next.Player2 := 8;

  if (ParticipantVisible(9)) and not EliminatedPlayer(9) then
      _Next.Player2 := 9;

  if (ParticipantVisible(10)) and not EliminatedPlayer(10) then
      _Next.Player2 := 10;

  if (ParticipantVisible(11)) and not EliminatedPlayer(11) then
      _Next.Player2 := 11;

  if (ParticipantVisible(12)) and not EliminatedPlayer(12) then
      _Next.Player2 := 12;

  if (ParticipantVisible(13)) and not EliminatedPlayer(13) then
      _Next.Player2 := 13;

  if (ParticipantVisible(14)) and not EliminatedPlayer(14) then
      _Next.Player2 := 14;

  if (ParticipantVisible(15)) and not EliminatedPlayer(15) then
      _Next.Player2 := 15;

  Result := _Next;

end;

function TScreenPartyTournamentRounds.Draw: boolean;
begin
  if DocumentUI <> nil then
  begin
    Exit(DocumentUI.Draw);
  end;
  DrawBG;
  DrawGrid();
  Result := DrawFG;
end;

procedure TScreenPartyTournamentRounds.DrawGrid();
var
  I, J: integer;
  MaxPhase: integer;
begin
  DrawGridBlock1();
  DrawGridBlock2();

  SetFontStyle(FontResult);
  SetFontSize(SizeResult);
  SetFontItalic(false);
  SetFontColor(ColorResult.R, ColorResult.G, ColorResult.B, 1);

  MaxPhase := PartyTournament.Phase;
  if (PartyTournament.Phase = 3) then
    MaxPhase := 2;

  // draw results
  for I := 0 to MaxPhase do
  begin
    for J := 0 to 15 do
    begin
      SetFontPos(PartyTournament.ResultPlayer[I, J].X, PartyTournament.ResultPlayer[I, J].Y);
      PrintText (PartyTournament.ResultPlayer[I, J].Text);
    end;
  end;

  // current players line
  for I := 0 to PartyTournament.Phase do
  begin
    DrawLinePlayer1(Lines[I, PartyTournament.Next.Player1, 0].X, Lines[I, PartyTournament.Next.Player1, 0].Y, Lines[I, PartyTournament.Next.Player1, 0].W, Lines[I, PartyTournament.Next.Player1, 0].H);
    DrawLinePlayer1(Lines[I, PartyTournament.Next.Player1, 1].X, Lines[I, PartyTournament.Next.Player1, 1].Y, Lines[I, PartyTournament.Next.Player1, 1].W, Lines[I, PartyTournament.Next.Player1, 1].H);

    DrawLinePlayer2(Lines[I, PartyTournament.Next.Player2, 0].X, Lines[I, PartyTournament.Next.Player2, 0].Y, Lines[I, PartyTournament.Next.Player2, 0].W, Lines[I, PartyTournament.Next.Player2, 0].H);
    DrawLinePlayer2(Lines[I, PartyTournament.Next.Player2, 1].X, Lines[I, PartyTournament.Next.Player2, 1].Y, Lines[I, PartyTournament.Next.Player2, 1].W, Lines[I, PartyTournament.Next.Player2, 1].H);
  end;

end;


procedure TScreenPartyTournamentRounds.DrawGridBlock1();
var
  X, Y, W, H, Y1, Y2,
  YQ1, YQ2, YQ3, YQ4,
  YS1, YS2, YF1: real;
  I: integer;
begin
  H := 5;
  W := 50;

  Y1 := 0;
  Y2 := 0;

  YQ1 := 0;
  YQ2 := 0;
  YQ3 := 0;
  YQ4 := 0;

  YS1 := 0;
  YS2 := 0;

  YF1 := 0;

  // left players block
  for I := 0 to 7 do
  begin
    X := Button[TextNamePlayer[0, I]].X + Button[TextNamePlayer[0, I]].W;
    Y := Button[TextNamePlayer[0, I]].Y + (Button[TextNamePlayer[0, I]].H - H) / 2;

    DrawLine(X, Y, W, H);
    Lines[0, I, 0].X := X;
    Lines[0, I, 0].Y := Y;
    Lines[0, I, 0].W := W;
    Lines[0, I, 0].H := H;

    if (Y1 = 0) then
      Y1 := Y
    else
    begin
      if (Y2 = 0) then
        Y2 := Y
      else
      begin

        DrawLine(X + W, Y1, H, Y2 - Y1 + H);

        Lines[0, I - 2, 1].X := X + W;
        Lines[0, I - 2, 1].Y := Y1;
        Lines[0, I - 2, 1].W := H;
        Lines[0, I - 2, 1].H := (Y2 - Y1 + H)/2;

        Lines[0, I - 1, 1].X := X + W;
        Lines[0, I - 1, 1].Y := Y1 + (Y2 - Y1 + H)/2;
        Lines[0, I - 1, 1].W := H;
        Lines[0, I - 1, 1].H := (Y2 - Y1 + H)/2;

        PartyTournament.ResultPlayer[0, I - 2].X := X + W + H + XResult;
        PartyTournament.ResultPlayer[0, I - 2].Y := Y1 + (Y2 - Y1 + H)/2 - YResult - SizeResult;

        PartyTournament.ResultPlayer[0, I - 1].X := X + W + H + XResult;
        PartyTournament.ResultPlayer[0, I - 1].Y := Y1 + (Y2 - Y1 + H)/2 + YResult;

        if (YQ1 = 0) then
          YQ1 := (Y2 - Y1)/2 + Y1
        else
        begin
          if (YQ2 = 0) then
            YQ2 := (Y2 - Y1)/2 + Y1
          else
          begin
            if (YQ3 = 0) then
              YQ3 := (Y2 - Y1)/2 + Y1
          end;
        end;

        Y1 := Y;
        Y2 := 0;
      end;
    end;

  end;

  // last
  YQ4 := (Y2 - Y1)/2 + Y1;
  DrawLine(X + W, Y1, H, Y2 - Y1 + H);

  Lines[0, 6, 1].X := X + W;
  Lines[0, 6, 1].Y := Y1;
  Lines[0, 6, 1].W := H;
  Lines[0, 6, 1].H := (Y2 - Y1 + H)/2;

  Lines[0, 7, 1].X := X + W;
  Lines[0, 7, 1].Y := Y1 + (Y2 - Y1 + H)/2;
  Lines[0, 7, 1].W := H;
  Lines[0, 7, 1].H := (Y2 - Y1 + H)/2;

  PartyTournament.ResultPlayer[0, 6].X := X + W + H + XResult;
  PartyTournament.ResultPlayer[0, 6].Y := Y1 + (Y2 - Y1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[0, 7].X := X + W + H + XResult;
  PartyTournament.ResultPlayer[0, 7].Y := Y1 + (Y2 - Y1 + H)/2 + YResult;

  // 4Final block 1
  DrawLine(X + W + H, YQ1, W - H, H);

  Lines[1, 0, 0].X := X + W;
  Lines[1, 0, 0].Y := YQ1;
  Lines[1, 0, 0].W := W;
  Lines[1, 0, 0].H := H;

  Lines[1, 1, 0].X := X + W;
  Lines[1, 1, 0].Y := YQ1;
  Lines[1, 1, 0].W := W;
  Lines[1, 1, 0].H := H;

  DrawLine(X + W + H, YQ2, W - H, H);

  Lines[1, 2, 0].X := X + W;
  Lines[1, 2, 0].Y := YQ2;
  Lines[1, 2, 0].W := W;
  Lines[1, 2, 0].H := H;

  Lines[1, 3, 0].X := X + W;
  Lines[1, 3, 0].Y := YQ2;
  Lines[1, 3, 0].W := W;
  Lines[1, 3, 0].H := H;

  DrawLine(X + W + H, YQ3, W - H, H);

  Lines[1, 4, 0].X := X + W;
  Lines[1, 4, 0].Y := YQ3;
  Lines[1, 4, 0].W := W;
  Lines[1, 4, 0].H := H;

  Lines[1, 5, 0].X := X + W;
  Lines[1, 5, 0].Y := YQ3;
  Lines[1, 5, 0].W := W;
  Lines[1, 5, 0].H := H;

  DrawLine(X + W + H, YQ4, W - H, H);

  Lines[1, 6, 0].X := X + W;
  Lines[1, 6, 0].Y := YQ4;
  Lines[1, 6, 0].W := W;
  Lines[1, 6, 0].H := H;

  Lines[1, 7, 0].X := X + W;
  Lines[1, 7, 0].Y := YQ4;
  Lines[1, 7, 0].W := W;
  Lines[1, 7, 0].H := H;

  DrawLine(X + W * 2, YQ1, H, YQ2 - YQ1 + H);

  Lines[1, 0, 1].X := X + W * 2;
  Lines[1, 0, 1].Y := YQ1;
  Lines[1, 0, 1].W := H;
  Lines[1, 0, 1].H := (YQ2 - YQ1 + H)/2;

  Lines[1, 1, 1].X := X + W * 2;
  Lines[1, 1, 1].Y := YQ1;
  Lines[1, 1, 1].W := H;
  Lines[1, 1, 1].H := (YQ2 - YQ1 + H)/2;

  Lines[1, 2, 1].X := X + W * 2;
  Lines[1, 2, 1].Y := YQ1 + (YQ2 - YQ1 + H)/2;
  Lines[1, 2, 1].W := H;
  Lines[1, 2, 1].H := (YQ2 - YQ1 + H)/2;

  Lines[1, 3, 1].X := X + W * 2;
  Lines[1, 3, 1].Y := YQ1 + (YQ2 - YQ1 + H)/2;
  Lines[1, 3, 1].W := H;
  Lines[1, 3, 1].H := (YQ2 - YQ1 + H)/2;

  PartyTournament.ResultPlayer[1, 0].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 0].Y := YQ1 + (YQ2 - YQ1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 1].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 1].Y := YQ1 + (YQ2 - YQ1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 2].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 2].Y := YQ1 + (YQ2 - YQ1 + H)/2 + YResult;

  PartyTournament.ResultPlayer[1, 3].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 3].Y := YQ1 + (YQ2 - YQ1 + H)/2 + YResult;

  DrawLine(X + W * 2, YQ3, H, YQ4 - YQ3 + H);

  Lines[1, 4, 1].X := X + W * 2;
  Lines[1, 4, 1].Y := YQ3;
  Lines[1, 4, 1].W := H;
  Lines[1, 4, 1].H := (YQ4 - YQ3 + H)/2;

  Lines[1, 5, 1].X := X + W * 2;
  Lines[1, 5, 1].Y := YQ3;
  Lines[1, 5, 1].W := H;
  Lines[1, 5, 1].H := (YQ4 - YQ3 + H)/2;

  Lines[1, 6, 1].X := X + W * 2;
  Lines[1, 6, 1].Y := YQ3 + (YQ4 - YQ3 + H)/2;
  Lines[1, 6, 1].W := H;
  Lines[1, 6, 1].H := (YQ4 - YQ3 + H)/2;

  Lines[1, 7, 1].X := X + W * 2;
  Lines[1, 7, 1].Y := YQ3 + (YQ4 - YQ3 + H)/2;
  Lines[1, 7, 1].W := H;
  Lines[1, 7, 1].H := (YQ4 - YQ3 + H)/2;

  PartyTournament.ResultPlayer[1, 4].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 4].Y := YQ3 + (YQ4 - YQ3 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 5].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 5].Y := YQ3 + (YQ4 - YQ3 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 6].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 6].Y := YQ3 + (YQ4 - YQ3 + H)/2 + YResult;

  PartyTournament.ResultPlayer[1, 7].X := X + W * 2 + H + XResult;
  PartyTournament.ResultPlayer[1, 7].Y := YQ3 + (YQ4 - YQ3 + H)/2 + YResult;

  // 2FinaL block 1
  YS1 := (YQ2 - YQ1)/2 + YQ1;
  YS2 := (YQ4 - YQ3)/2 + YQ3;

  DrawLine(X + W * 2 + H, YS1, W - H, H);

  Lines[2, 0, 0].X := X + W * 2;
  Lines[2, 0, 0].Y := YS1;
  Lines[2, 0, 0].W := W;
  Lines[2, 0, 0].H := H;

  Lines[2, 1, 0].X := X + W * 2;
  Lines[2, 1, 0].Y := YS1;
  Lines[2, 1, 0].W := W;
  Lines[2, 1, 0].H := H;

  Lines[2, 2, 0].X := X + W * 2;
  Lines[2, 2, 0].Y := YS1;
  Lines[2, 2, 0].W := W;
  Lines[2, 2, 0].H := H;

  Lines[2, 3, 0].X := X + W * 2;
  Lines[2, 3, 0].Y := YS1;
  Lines[2, 3, 0].W := W;
  Lines[2, 3, 0].H := H;

  DrawLine(X + W * 2 + H, YS2, W - H, H);

  Lines[2, 4, 0].X := X + W * 2;
  Lines[2, 4, 0].Y := YS2;
  Lines[2, 4, 0].W := W;
  Lines[2, 4, 0].H := H;

  Lines[2, 5, 0].X := X + W * 2;
  Lines[2, 5, 0].Y := YS2;
  Lines[2, 5, 0].W := W;
  Lines[2, 5, 0].H := H;

  Lines[2, 6, 0].X := X + W * 2;
  Lines[2, 6, 0].Y := YS2;
  Lines[2, 6, 0].W := W;
  Lines[2, 6, 0].H := H;

  Lines[2, 7, 0].X := X + W * 2;
  Lines[2, 7, 0].Y := YS2;
  Lines[2, 7, 0].W := W;
  Lines[2, 7, 0].H := H;

  DrawLine(X + W * 3, YS1, H, YS2 - YS1 + H);

  Lines[2, 0, 1].X := X + W * 3;
  Lines[2, 0, 1].Y := YS1;
  Lines[2, 0, 1].W := H;
  Lines[2, 0, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 1, 1].X := X + W * 3;
  Lines[2, 1, 1].Y := YS1;
  Lines[2, 1, 1].W := H;
  Lines[2, 1, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 2, 1].X := X + W * 3;
  Lines[2, 2, 1].Y := YS1;
  Lines[2, 2, 1].W := H;
  Lines[2, 2, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 3, 1].X := X + W * 3;
  Lines[2, 3, 1].Y := YS1;
  Lines[2, 3, 1].W := H;
  Lines[2, 3, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 4, 1].X := X + W * 3;
  Lines[2, 4, 1].Y := YS1 + (YS2 - YS1 + H)/2;
  Lines[2, 4, 1].W := H;
  Lines[2, 4, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 5, 1].X := X + W * 3;
  Lines[2, 5, 1].Y := YS1 + (YS2 - YS1 + H)/2;
  Lines[2, 5, 1].W := H;
  Lines[2, 5, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 6, 1].X := X + W * 3;
  Lines[2, 6, 1].Y := YS1 + (YS2 - YS1 + H)/2;
  Lines[2, 6, 1].W := H;
  Lines[2, 6, 1].H := (YS2 - YS1 + H)/2;

  Lines[2, 7, 1].X := X + W * 3;
  Lines[2, 7, 1].Y := YS1 + (YS2 - YS1 + H)/2;
  Lines[2, 7, 1].W := H;
  Lines[2, 7, 1].H := (YS2 - YS1 + H)/2;

  PartyTournament.ResultPlayer[2, 0].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 0].Y := YS1 + (YS2 - YS1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[2, 1].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 1].Y := YS1 + (YS2 - YS1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[2, 2].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 2].Y := YS1 + (YS2 - YS1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[2, 3].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 3].Y := YS1 + (YS2 - YS1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[2, 4].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 4].Y := YS1 + (YS2 - YS1 + H)/2 + YResult;

  PartyTournament.ResultPlayer[2, 5].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 5].Y := YS1 + (YS2 - YS1 + H)/2 + YResult;

  PartyTournament.ResultPlayer[2, 6].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 6].Y := YS1 + (YS2 - YS1 + H)/2 + YResult;

  PartyTournament.ResultPlayer[2, 7].X := X + W * 3 + H + XResult;
  PartyTournament.ResultPlayer[2, 7].Y := YS1 + (YS2 - YS1 + H)/2 + YResult;

  // Final block 1
  YF1 := (YS2 - YS1)/2 + YS1;
  DrawLine(X + W * 3 + H, YF1, W - H, H);

  for I := 0 to 7 do
  begin
    Lines[3, I, 0].X := X + W * 3;
    Lines[3, I, 0].Y := YF1;
    Lines[3, I, 0].W := W;
    Lines[3, I, 0].H := H;
  end;

end;

procedure TScreenPartyTournamentRounds.DrawGridBlock2();
var
  X, Y, W, H, Y1, Y2,
  YQ1, YQ2, YQ3, YQ4,
  YS1, YS2, YF1: real;
  I: integer;
begin

  H := 5;
  W := 50;

  Y1 := 0;
  Y2 := 0;

  YQ1 := 0;
  YQ2 := 0;
  YQ3 := 0;
  YQ4 := 0;

  YS1 := 0;
  YS2 := 0;

  YF1 := 0;

  // right players block
  for I := 0 to 7 do
  begin
    X := Button[TextNamePlayer[1, I]].X - W;
    Y := Button[TextNamePlayer[1, I]].Y + (Button[TextNamePlayer[0, I]].H - H) / 2;

    DrawLine(X, Y, W, H);
    Lines[0, I + 8, 0].X := X;
    Lines[0, I + 8, 0].Y := Y;
    Lines[0, I + 8, 0].W := W;
    Lines[0, I + 8, 0].H := H;

    if (Y1 = 0) then
      Y1 := Y
    else
    begin
      if (Y2 = 0) then
        Y2 := Y
      else
      begin

        DrawLine(X - H, Y1, H, Y2 - Y1 + H);

        Lines[0, I + 6, 1].X := X - H;
        Lines[0, I + 6, 1].Y := Y1;
        Lines[0, I + 6, 1].W := H;
        Lines[0, I + 6, 1].H := (Y2 - Y1 + H)/2;

        Lines[0, I + 7, 1].X := X - H;
        Lines[0, I + 7, 1].Y := Y1 + (Y2 - Y1 +H)/2;
        Lines[0, I + 7, 1].W := H;
        Lines[0, I + 7, 1].H := (Y2 - Y1 + H)/2;

        PartyTournament.ResultPlayer[0, I + 6].X := X + H - SizeResult - XResult;
        PartyTournament.ResultPlayer[0, I + 6].Y := Y1 + (Y2 - Y1 + H)/2 - YResult - SizeResult;

        PartyTournament.ResultPlayer[0, I + 7].X := X + H - SizeResult - XResult;
        PartyTournament.ResultPlayer[0, I + 7].Y := Y1 + (Y2 - Y1 + H)/2 + YResult;

        if (YQ1 = 0) then
          YQ1 := (Y2 - Y1)/2 + Y1
        else
        begin
          if (YQ2 = 0) then
            YQ2 := (Y2 - Y1)/2 + Y1
          else
          begin
            if (YQ3 = 0) then
              YQ3 := (Y2 - Y1)/2 + Y1
          end;
        end;

        Y1 := Y;
        Y2 := 0;
      end;
    end;

  end;

  // last
  DrawLine(X - H, Y1, H, Y2 - Y1 + H);
  YQ4 := (Y2 - Y1)/2 + Y1;

  Lines[0, 14, 1].X := X - H;
  Lines[0, 14, 1].Y := Y1;
  Lines[0, 14, 1].W := H;
  Lines[0, 14, 1].H := (Y2 - Y1 + H)/2;

  Lines[0, 15, 1].X := X - H;
  Lines[0, 15, 1].Y := Y1 + (Y2 - Y1 + H)/2;
  Lines[0, 15, 1].W := H;
  Lines[0, 15, 1].H := (Y2 - Y1 + H)/2;

  PartyTournament.ResultPlayer[0, 14].X := X + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[0, 14].Y := Y1 + (Y2 - Y1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[0, 15].X := X + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[0, 15].Y := Y1 + (Y2 - Y1 + H)/2 + YResult;

  // 4Final block 2
  DrawLine(X - W, YQ1, W - H, H);

  Lines[1, 8, 0].X := X - W;
  Lines[1, 8, 0].Y := YQ1;
  Lines[1, 8, 0].W := W;
  Lines[1, 8, 0].H := H;

  Lines[1, 9, 0].X := X - W;
  Lines[1, 9, 0].Y := YQ1;
  Lines[1, 9, 0].W := W;
  Lines[1, 9, 0].H := H;

  DrawLine(X - W, YQ2, W - H, H);

  Lines[1, 10, 0].X := X - W;
  Lines[1, 10, 0].Y := YQ2;
  Lines[1, 10, 0].W := W;
  Lines[1, 10, 0].H := H;

  Lines[1, 11, 0].X := X - W;
  Lines[1, 11, 0].Y := YQ2;
  Lines[1, 11, 0].W := W;
  Lines[1, 11, 0].H := H;

  DrawLine(X - W, YQ3, W - H, H);

  Lines[1, 12, 0].X := X - W;
  Lines[1, 12, 0].Y := YQ3;
  Lines[1, 12, 0].W := W;
  Lines[1, 12, 0].H := H;

  Lines[1, 13, 0].X := X - W;
  Lines[1, 13, 0].Y := YQ3;
  Lines[1, 13, 0].W := W;
  Lines[1, 13, 0].H := H;

  DrawLine(X - W, YQ4, W - H, H);

  Lines[1, 14, 0].X := X - W;
  Lines[1, 14, 0].Y := YQ4;
  Lines[1, 14, 0].W := W;
  Lines[1, 14, 0].H := H;

  Lines[1, 15, 0].X := X - W;
  Lines[1, 15, 0].Y := YQ4;
  Lines[1, 15, 0].W := W;
  Lines[1, 15, 0].H := H;

  DrawLine(X - W - H, YQ1, H, YQ2 - YQ1 + H);

  Lines[1, 8, 1].X := X - W - H;
  Lines[1, 8, 1].Y := YQ1;
  Lines[1, 8, 1].W := H;
  Lines[1, 8, 1].H := (YQ2 - YQ1 + H)/2;

  Lines[1, 9, 1].X := X - W - H;
  Lines[1, 9, 1].Y := YQ1;
  Lines[1, 9, 1].W := H;
  Lines[1, 9, 1].H := (YQ2 - YQ1 + H)/2;

  Lines[1, 10, 1].X := X - W - H;
  Lines[1, 10, 1].Y := YQ1 + (YQ2 - YQ1 + H)/2;
  Lines[1, 10, 1].W := H;
  Lines[1, 10, 1].H := (YQ2 - YQ1 + H)/2;

  Lines[1, 11, 1].X := X - W - H;
  Lines[1, 11, 1].Y := YQ1 + (YQ2 - YQ1 + H)/2;
  Lines[1, 11, 1].W := H;
  Lines[1, 11, 1].H := (YQ2 - YQ1 + H)/2;

  PartyTournament.ResultPlayer[1, 8].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 8].Y := YQ1 + (YQ2 - YQ1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 9].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 9].Y := YQ1 + (YQ2 - YQ1 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 10].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 10].Y := YQ1 + (YQ2 - YQ1 + H)/2 + YResult;

  PartyTournament.ResultPlayer[1, 11].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 11].Y := YQ1 + (YQ2 - YQ1 + H)/2 + YResult;

  DrawLine(X - W - H, YQ3, H, YQ4 - YQ3 + H);

  Lines[1, 12, 1].X := X - W - H;
  Lines[1, 12, 1].Y := YQ3;
  Lines[1, 12, 1].W := H;
  Lines[1, 12, 1].H := (YQ4 - YQ3 + H)/2;

  Lines[1, 13, 1].X := X - W - H;
  Lines[1, 13, 1].Y := YQ3;
  Lines[1, 13, 1].W := H;
  Lines[1, 13, 1].H := (YQ4 - YQ3 + H)/2;

  Lines[1, 14, 1].X := X - W - H;
  Lines[1, 14, 1].Y := YQ3 + (YQ4 - YQ3 + H)/2;
  Lines[1, 14, 1].W := H;
  Lines[1, 14, 1].H := (YQ4 - YQ3 + H)/2;

  Lines[1, 15, 1].X := X - W - H;
  Lines[1, 15, 1].Y := YQ3 + (YQ4 - YQ3 + H)/2;
  Lines[1, 15, 1].W := H;
  Lines[1, 15, 1].H := (YQ4 - YQ3 + H)/2;

  PartyTournament.ResultPlayer[1, 12].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 12].Y := YQ3 + (YQ4 - YQ3 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 13].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 13].Y := YQ3 + (YQ4 - YQ3 + H)/2 - YResult - SizeResult;

  PartyTournament.ResultPlayer[1, 14].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 14].Y := YQ3 + (YQ4 - YQ3 + H)/2 + YResult;

  PartyTournament.ResultPlayer[1, 15].X := X - W + H - SizeResult - XResult;
  PartyTournament.ResultPlayer[1, 15].Y := YQ3 + (YQ4 - YQ3 + H)/2 + YResult;

  // 2FinaL block 2
  YS1 := (YQ2 - YQ1)/2 + YQ1;
  YS2 := (YQ4 - YQ3)/2 + YQ3;

  DrawLine(X - W * 2, YS1, W - H, H);

  Lines[2, 8, 0].X := X - W * 2;
  Lines[2, 8, 0].Y := YS1;
  Lines[2, 8, 0].W := W;
  Lines[2, 8, 0].H := H;

  Lines[2, 9, 0].X := X - W * 2;
  Lines[2, 9, 0].Y := YS1;
  Lines[2, 9, 0].W := W;
  Lines[2, 9, 0].H := H;

  Lines[2, 10, 0].X := X - W * 2;
  Lines[2, 10, 0].Y := YS1;
  Lines[2, 10, 0].W := W;
  Lines[2, 10, 0].H := H;

  Lines[2, 11, 0].X := X - W * 2;
  Lines[2, 11, 0].Y := YS1;
  Lines[2, 11, 0].W := W;
  Lines[2, 11, 0].H := H;

  DrawLine(X - W * 2, YS2, W - H, H);

  Lines[2, 12, 0].X := X - W * 2;
  Lines[2, 12, 0].Y := YS2;
  Lines[2, 12, 0].W := W;
  Lines[2, 12, 0].H := H;

  Lines[2, 13, 0].X := X - W * 2;
  Lines[2, 13, 0].Y := YS2;
  Lines[2, 13, 0].W := W;
  Lines[2, 13, 0].H := H;

  Lines[2, 14, 0].X := X - W * 2;
  Lines[2, 14, 0].Y := YS2;
  Lines[2, 14, 0].W := W;
  Lines[2, 14, 0].H := H;

  Lines[2, 15, 0].X := X - W * 2;
  Lines[2, 15, 0].Y := YS2;
  Lines[2, 15, 0].W := W;
  Lines[2, 15, 0].H := H;

  DrawLine(X - W * 2 - H, YS1, H, YS2 - YS1 + H);
  for I := 8 to 11 do
  begin
    Lines[2, I, 1].X := X - W * 2 - H;
    Lines[2, I, 1].Y := YS1;
    Lines[2, I, 1].W := H;
    Lines[2, I, 1].H := (YS2 - YS1 + H)/2;

    PartyTournament.ResultPlayer[2, I].X := X - W * 2 + H - SizeResult - XResult;
    PartyTournament.ResultPlayer[2, I].Y := YS1 + (YS2 - YS1 + H)/2 - YResult - SizeResult;
  end;

  for I := 12 to 15 do
  begin
    Lines[2, I, 1].X := X - W * 2 - H;
    Lines[2, I, 1].Y := YS1 + (YS2 - YS1 + H)/2;
    Lines[2, I, 1].W := H;
    Lines[2, I, 1].H := (YS2 - YS1 + H)/2;

    PartyTournament.ResultPlayer[2, I].X := X - W * 2 + H - SizeResult - XResult;
    PartyTournament.ResultPlayer[2, I].Y := YS1 + (YS2 - YS1 + H)/2 + YResult;
  end;

  // Final block 2
  YF1 := (YS2 - YS1)/2 + YS1;
  DrawLine(X - W * 3, YF1, W - H, H);

  for I := 8 to 15 do
  begin
    Lines[3, I, 0].X := X - W * 3;
    Lines[3, I, 0].Y := YF1;
    Lines[3, I, 0].W := W;
    Lines[3, I, 0].H := H;
  end;

end;

procedure TScreenPartyTournamentRounds.DrawLine(X, Y, W, H: real);
begin
  Renderer.DrawQuad(X, Y, 0, W, H, 1, 1, 1, 0.4);
end;

procedure TScreenPartyTournamentRounds.DrawLinePlayer1(X, Y, W, H: real);
var
  R, G, B: real;
begin

  if not(PartyTournament.TournamentFinish) and (Interaction = PartyTournament.Next.Player1) then
  begin
    R := R1;
    G := G1;
    B := B1;
  end
  else
  begin
    R := DR1;
    G := DG1;
    B := DB1;
  end;

  Renderer.DrawQuad(X, Y, 0, W, H, R, G, B, 1);
end;

procedure TScreenPartyTournamentRounds.DrawLinePlayer2(X, Y, W, H: real);
var
  R, G, B: real;
begin

  if not(PartyTournament.TournamentFinish) and (Interaction = PartyTournament.Next.Player2) then
  begin
    R := R2;
    G := G2;
    B := B2;
  end
  else
  begin
    R := DR2;
    G := DG2;
    B := DB2;
  end;

  Renderer.DrawQuad(X, Y, 0, W, H, R, G, B, 1);
end;

end.
