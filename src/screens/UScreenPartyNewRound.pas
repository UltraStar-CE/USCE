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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenPartyNewRound.pas $
 * $Id: UScreenPartyNewRound.pas 2246 2010-04-18 13:43:36Z tobigun $
 *}

unit UScreenPartyNewRound;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UDocumentUI,
  UFiles,
  UMenu,
  UMusic,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenPartyNewRound = class(TMenu)
    private
      VisibleRound:  Integer;
      DocumentUI: TDocumentUI;
      procedure SetDocumentState;
      procedure ScrollDocumentRounds(Delta: integer);

    public
      //Texts:
      TextRound: array [0..6] of cardinal;

      TextWinner: array [0..6] of cardinal;

      TextNextRound: cardinal;
      TextNextRoundNo: cardinal;
      TextNextPlayer1: cardinal;
      TextNextPlayer2: cardinal;
      TextNextPlayer3: cardinal;

      //Statics
      StaticRound: array [0..6] of cardinal;

      //Scores
      TextScoreTeam1: cardinal;
      TextScoreTeam2: cardinal;
      TextScoreTeam3: cardinal;
      TextNameTeam1: cardinal;
      TextNameTeam2: cardinal;
      TextNameTeam3: cardinal;

      TextTeam1Players: cardinal;
      TextTeam2Players: cardinal;
      TextTeam3Players: cardinal;

      StaticTeam1: cardinal;
      StaticTeam2: cardinal;
      StaticTeam3: cardinal;
      StaticNextPlayer1: cardinal;
      StaticNextPlayer2: cardinal;
      StaticNextPlayer3: cardinal;



      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      procedure Refresh;
  end;

const
  uiPartyNewRoundRole = 'party-new-round';
  uiPartyNewRoundData = 'partyNewRound';
  uiPartyNewRoundContinue = 'party.new-round.continue';
  uiPartyNewRoundPrevious = 'party.new-round.previous';
  uiPartyNewRoundNext = 'party.new-round.next';
  ID='ID_033';   //for help system

implementation

uses
  UCommon,
  UGraphic,
  UHelp,
  UIni,
  ULanguage,
  ULog,
  UMain,
  UParty,
  USong,
  UUnicodeUtils,
  USkins,
  Math;

procedure TScreenPartyNewRound.SetDocumentState;
var I, J, ColorIndex, ModeIndex, NextPlayer: integer; Prefix, ModeName: UTF8String;
    Players: array of UTF8String; Col: TRGB;
  function ColorText(const Value: TRGB): UTF8String;
  begin
    Result := '#' + IntToHex(EnsureRange(Round(Value.R * 255), 0, 255), 2) +
      IntToHex(EnsureRange(Round(Value.G * 255), 0, 255), 2) +
      IntToHex(EnsureRange(Round(Value.B * 255), 0, 255), 2);
  end;
  function TeamColor(Team: integer): UTF8String;
  begin
    Col.R := 1; Col.G := 1; Col.B := 1;
    ColorIndex := ColorExists('P' + IntToStr(Team + 1) + 'Dark');
    if ColorIndex <> -1 then Col := Color[ColorIndex].RGB;
    Result := ColorText(Col);
  end;
begin
  DocumentUI.SetModel(uiPartyNewRoundData + '.current', IntToStr(Party.CurrentRound + 1), 1);
  ModeName := '';
  if (Party.CurrentRound >= 0) and (Party.CurrentRound <= High(Party.Rounds)) then
  begin
    ModeIndex := Party.Rounds[Party.CurrentRound].Mode;
    if (ModeIndex >= 0) and (ModeIndex <= High(Party.Modes)) then
      ModeName := Language.Translate('MODE_' + UpperCase(Party.Modes[ModeIndex].Name) + '_DESC');
  end;
  DocumentUI.SetValue(uiPartyNewRoundData + '.description', ModeName);
  DocumentUI.SetArray(uiPartyNewRoundData + '.teams', Length(Party.Teams));
  for I := 0 to High(Party.Teams) do
  begin
    Prefix := uiPartyNewRoundData + '.teams[' + IntToStr(I) + '].';
    DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
    DocumentUI.SetModel(Prefix + 'name', UTF8String(Party.Teams[I].Name));
    DocumentUI.SetModel(Prefix + 'score', IntToStr(Party.Teams[I].Score), 1);
    DocumentUI.SetModel(Prefix + 'color', TeamColor(I));
    // Modern's next-player cards all inherit the first card's color.
    DocumentUI.SetModel(Prefix + 'nextColor', TeamColor(0));
    SetLength(Players, Length(Party.Teams[I].Players));
    for J := 0 to High(Party.Teams[I].Players) do Players[J] := UTF8String(Party.Teams[I].Players[J].Name);
    DocumentUI.SetModel(Prefix + 'players', Language.Implode(Players));
    NextPlayer := Party.Teams[I].NextPlayer;
    if (NextPlayer >= 0) and (NextPlayer <= High(Party.Teams[I].Players)) then
      DocumentUI.SetModel(Prefix + 'next', UTF8String(Party.Teams[I].Players[NextPlayer].Name))
    else DocumentUI.SetModel(Prefix + 'next', '');
  end;
  DocumentUI.SetArray(uiPartyNewRoundData + '.rounds', Length(Party.Rounds));
  for I := 0 to High(Party.Rounds) do
  begin
    Prefix := uiPartyNewRoundData + '.rounds[' + IntToStr(I) + '].';
    ModeName := '';
    ModeIndex := Party.Rounds[I].Mode;
    if (ModeIndex >= 0) and (ModeIndex <= High(Party.Modes)) then
      ModeName := Language.Translate('MODE_' + UpperCase(Party.Modes[ModeIndex].Name) + '_NAME');
    DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
    DocumentUI.SetModel(Prefix + 'title', IntToStr(I + 1) + ') ' + ModeName);
    DocumentUI.SetModel(Prefix + 'winner', Party.GetWinnerString(I));
    DocumentUI.SetModel(Prefix + 'current', IntToStr(Ord(I = Party.CurrentRound)), 2);
  end;
end;

procedure TScreenPartyNewRound.ScrollDocumentRounds(Delta: integer);
var Viewport, FirstRow: TDocumentRegion;
begin
  if Length(Party.Rounds) = 0 then Exit;
  VisibleRound := EnsureRange(VisibleRound + Delta, 0, High(Party.Rounds));
  DocumentUI.Reveal('party-new-round-row-' + IntToStr(VisibleRound));
  // The document defines row pitch and viewport capacity. Retain the actual
  // clamped scroll position rather than a game-side fixed visible-row count.
  if DocumentUI.Region('party-new-round-rounds', Viewport) and
     DocumentUI.Region('party-new-round-row-0', FirstRow) and (FirstRow.H > 0) then
    VisibleRound := EnsureRange(Round((Viewport.Y - FirstRow.Y) / FirstRow.H), 0, High(Party.Rounds));
end;

destructor TScreenPartyNewRound.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenPartyNewRound.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenPartyNewRound.DrawFG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(false, true) else Result := inherited;
end;

function TScreenPartyNewRound.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action: UTF8String;
begin
  if DocumentUI = nil then Exit(inherited);
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown) else DocumentUI.Mouse(X, Y);
  if BtnDown then
  begin
    if MouseButton = SDL_BUTTON_WHEELUP then ScrollDocumentRounds(-1)
    else if MouseButton = SDL_BUTTON_WHEELDOWN then ScrollDocumentRounds(1);
  end;
  Action := DocumentUI.TakeAction;
  Result := true;
  if Action = uiPartyNewRoundContinue then Result := ParseInput(SDLK_RETURN, 0, true)
  else if Action = uiPartyNewRoundPrevious then ScrollDocumentRounds(-1)
  else if Action = uiPartyNewRoundNext then ScrollDocumentRounds(1)
  else if Action = uiNavigationBack then Result := ParseInput(SDLK_ESCAPE, 0, true);
end;

function TScreenPartyNewRound.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
begin
  Result := true;
  if (PressedDown) then
  begin // Key Down
    if DocumentUI <> nil then
      case PressedKey of
        SDLK_UP: begin ScrollDocumentRounds(-1); Exit; end;
        SDLK_DOWN: begin ScrollDocumentRounds(1); Exit; end;
      end;
    // check normal keys
    case PressedKey of
      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE :
        begin
          AudioPlayback.PlaySound(SoundLib.Back);
          CheckFadeTo(@ScreenMain,'MSG_END_PARTY');
        end;

      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;

      SDLK_RETURN:
        begin
          AudioPlayback.PlaySound(SoundLib.Start);
          Party.CallBeforeSongSelect;
        end;

      SDLK_UP:
        begin
         if VisibleRound > 0 then
         begin
           Dec(VisibleRound);
           Refresh;
         end;
        end;

      SDLK_DOWN:
        begin
          if VisibleRound < (Length(Party.Rounds) - 7) then
          begin
            Inc(VisibleRound);
            Refresh;
          end;
        end;
    end;
  end;
end;

procedure TScreenPartyNewRound.Refresh;
var
  N, I: Integer;
  NumRounds: Integer;
begin
  if DocumentUI <> nil then
  begin
    SetDocumentState;
    ScrollDocumentRounds(0);
    Exit;
  end;
  //Set Visibility of Round Infos
  NumRounds := Length(Party.Rounds);

  N := VisibleRound;

  if ((NumRounds-7) < N) then
  begin
    N := NumRounds - 7;
    VisibleRound := N;
  end;

  if (N < 0) then
  begin
    N := 0;
    VisibleRound := 0;
  end;

  //Set Visibility of Round Infos
  for I := 0 to 6 do
  begin
    if (I <= High(Party.Rounds)) then
    begin
      Statics[StaticRound[I]].Visible := True;
      Text[TextRound[I]].Visible := True;
      Text[TextWinner[I]].Visible := True;

      // update texts:
      Text[TextRound[I]].Text := IntToStr(I + 1 + N)+') ' + Language.Translate('MODE_' + uppercase(Party.Modes[Party.Rounds[I + N].Mode].Name) + '_NAME');
      Text[TextWinner[I]].Text := Party.GetWinnerString(I + N);
    end
    else
    begin
      Statics[StaticRound[I]].Visible := False;
      Text[TextRound[I]].Visible := False;
      Text[TextWinner[I]].Visible := False;
    end;
  end;
end;

constructor TScreenPartyNewRound.Create;
begin
  inherited Create;
  DocumentUI := TDocumentUI.Open(uiPartyNewRoundRole);
  if DocumentUI <> nil then Exit;

  TextRound[0] := AddText (Theme.PartyNewRound.TextRound1);
  TextRound[1] := AddText (Theme.PartyNewRound.TextRound2);
  TextRound[2] := AddText (Theme.PartyNewRound.TextRound3);
  TextRound[3] := AddText (Theme.PartyNewRound.TextRound4);
  TextRound[4] := AddText (Theme.PartyNewRound.TextRound5);
  TextRound[5] := AddText (Theme.PartyNewRound.TextRound6);
  TextRound[6] := AddText (Theme.PartyNewRound.TextRound7);

  TextWinner[0] := AddText (Theme.PartyNewRound.TextWinner1);
  TextWinner[1] := AddText (Theme.PartyNewRound.TextWinner2);
  TextWinner[2] := AddText (Theme.PartyNewRound.TextWinner3);
  TextWinner[3] := AddText (Theme.PartyNewRound.TextWinner4);
  TextWinner[4] := AddText (Theme.PartyNewRound.TextWinner5);
  TextWinner[5] := AddText (Theme.PartyNewRound.TextWinner6);
  TextWinner[6] := AddText (Theme.PartyNewRound.TextWinner7);

  TextNextRound := AddText (Theme.PartyNewRound.TextNextRound);
  TextNextRoundNo := AddText (Theme.PartyNewRound.TextNextRoundNo);
  TextNextPlayer1 := AddText (Theme.PartyNewRound.TextNextPlayer1);
  TextNextPlayer2 := AddText (Theme.PartyNewRound.TextNextPlayer2);
  TextNextPlayer3 := AddText (Theme.PartyNewRound.TextNextPlayer3);

  StaticRound[0] := AddStatic (Theme.PartyNewRound.StaticRound1);
  StaticRound[1] := AddStatic (Theme.PartyNewRound.StaticRound2);
  StaticRound[2] := AddStatic (Theme.PartyNewRound.StaticRound3);
  StaticRound[3] := AddStatic (Theme.PartyNewRound.StaticRound4);
  StaticRound[4] := AddStatic (Theme.PartyNewRound.StaticRound5);
  StaticRound[5] := AddStatic (Theme.PartyNewRound.StaticRound6);
  StaticRound[6] := AddStatic (Theme.PartyNewRound.StaticRound7);

  //Scores
  TextScoreTeam1 := AddText (Theme.PartyNewRound.TextScoreTeam1);
  TextScoreTeam2 := AddText (Theme.PartyNewRound.TextScoreTeam2);
  TextScoreTeam3 := AddText (Theme.PartyNewRound.TextScoreTeam3);
  TextNameTeam1 := AddText (Theme.PartyNewRound.TextNameTeam1);
  TextNameTeam2 := AddText (Theme.PartyNewRound.TextNameTeam2);
  TextNameTeam3 := AddText (Theme.PartyNewRound.TextNameTeam3);

  //Players
  TextTeam1Players := AddText (Theme.PartyNewRound.TextTeam1Players);
  TextTeam2Players := AddText (Theme.PartyNewRound.TextTeam2Players);
  TextTeam3Players := AddText (Theme.PartyNewRound.TextTeam3Players);

  StaticTeam1 := AddStatic (Theme.PartyNewRound.StaticTeam1);
  StaticTeam2 := AddStatic (Theme.PartyNewRound.StaticTeam2);
  StaticTeam3 := AddStatic (Theme.PartyNewRound.StaticTeam3);
  StaticNextPlayer1 := AddStatic (Theme.PartyNewRound.StaticNextPlayer1);
  StaticNextPlayer2 := AddStatic (Theme.PartyNewRound.StaticNextPlayer2);
  StaticNextPlayer3 := AddStatic (Theme.PartyNewRound.StaticNextPlayer3);

  LoadFromTheme(Theme.PartyNewRound);
end;

procedure TScreenPartyNewRound.OnShow;
  function GetTeamPlayers(const Num: integer): UTF8String;
  var
    Players: array of UTF8String;
    J: integer;
  begin
    if (Num > High(Party.Teams)) or (Num < 0) then
      exit;

    //Create Players array
    SetLength(Players, Length(Party.Teams[Num].Players));
    For J := 0 to High(Party.Teams[Num].Players) do
      Players[J] := UTF8String(Party.Teams[Num].Players[J].Name);

    //Implode and Return
    Result := Language.Implode(Players);
  end;
begin
  if DocumentUI = nil then inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenPartyNewRound');

  if (Party.CurrentRound > 0) then
  begin
    if (Party.CurrentRound > 1) then
      VisibleRound := Party.CurrentRound - 2
    else
      VisibleRound := Party.CurrentRound - 1;
  end;

  Refresh;
  if DocumentUI <> nil then Exit;

  //Display Scores
  if (Length(Party.Teams) >= 1) then
  begin
    Text[TextScoreTeam1].Text := InttoStr(Party.Teams[0].Score);
    Text[TextNameTeam1].Text := UTF8String(Party.Teams[0].Name);
    Text[TextTeam1Players].Text := GetTeamPlayers(0);

    Text[TextScoreTeam1].Visible := true;
    Text[TextNameTeam1].Visible := true;
    Text[TextTeam1Players].Visible := true;
    Statics[StaticTeam1].Visible := true;
    Statics[StaticNextPlayer1].Visible := true;
  end
  else
  begin
    Text[TextScoreTeam1].Visible := false;
    Text[TextNameTeam1].Visible := false;
    Text[TextTeam1Players].Visible := false;
    Statics[StaticTeam1].Visible := false;
    Statics[StaticNextPlayer1].Visible := false;
  end;

  if (Length(Party.Teams) >= 2) then
  begin
    Text[TextScoreTeam2].Text := InttoStr(Party.Teams[1].Score);
    Text[TextNameTeam2].Text := UTF8String(Party.Teams[1].Name);
    Text[TextTeam2Players].Text := GetTeamPlayers(1);

    Text[TextScoreTeam2].Visible := true;
    Text[TextNameTeam2].Visible := true;
    Text[TextTeam2Players].Visible := true;
    Statics[StaticTeam2].Visible := true;
    Statics[StaticNextPlayer2].Visible := true;
  end
  else
  begin
    Text[TextScoreTeam2].Visible := false;
    Text[TextNameTeam2].Visible := false;
    Text[TextTeam2Players].Visible := false;
    Statics[StaticTeam2].Visible := false;
    Statics[StaticNextPlayer2].Visible := false;
  end;

  if (Length(Party.Teams) >= 3) then
  begin
    Text[TextScoreTeam3].Text := InttoStr(Party.Teams[2].Score);
    Text[TextNameTeam3].Text := UTF8String(Party.Teams[2].Name);
    Text[TextTeam3Players].Text := GetTeamPlayers(2);

    Text[TextScoreTeam3].Visible := true;
    Text[TextNameTeam3].Visible := true;
    Text[TextTeam3Players].Visible := true;
    Statics[StaticTeam3].Visible := true;
    Statics[StaticNextPlayer3].Visible := true;
  end
  else
  begin
    Text[TextScoreTeam3].Visible := false;
    Text[TextNameTeam3].Visible := false;
    Text[TextTeam3Players].Visible := false;
    Statics[StaticTeam3].Visible := false;
    Statics[StaticNextPlayer3].Visible := false;
  end;

  //nextRound Texts
  Text[TextNextRound].Text := Language.Translate('MODE_' + uppercase(Party.Modes[Party.Rounds[Party.CurrentRound].Mode].Name) + '_DESC');

  Text[TextNextRoundNo].Text := InttoStr(Party.CurrentRound + 1);
  if (Length(Party.Teams) >= 1) then
  begin
    Text[TextNextPlayer1].Text := Party.Teams[0].Players[Party.Teams[0].NextPlayer].Name;
    Text[TextNextPlayer1].Visible := true;
  end
  else
    Text[TextNextPlayer1].Visible := false;

  if (Length(Party.Teams) >= 2) then
  begin
    Text[TextNextPlayer2].Text := Party.Teams[1].Players[Party.Teams[1].NextPlayer].Name;
    Text[TextNextPlayer2].Visible := true;
  end
  else
    Text[TextNextPlayer2].Visible := false;

  if (Length(Party.Teams) >= 3) then
  begin
    Text[TextNextPlayer3].Text := Party.Teams[2].Players[Party.Teams[2].NextPlayer].Name;
    Text[TextNextPlayer3].Visible := true;
  end
  else
    Text[TextNextPlayer3].Visible := false;
end;

end.
