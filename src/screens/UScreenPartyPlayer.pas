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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenPartyPlayer.pas $
 * $Id: UScreenPartyPlayer.pas 2201 2010-03-15 21:14:51Z brunzelchen $
 *}

unit UScreenPartyPlayer;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UDisplay,
  UDocumentUI,
  URecentNames,
  UFiles,
  UMenu,
  UMusic,
  UNote,
  UParty,
  UScreenSingController,
  UScreenPartyNewRound,
  UScreenPartyScore,
  UScreenPartyWin,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenPartyPlayer = class(TMenu)
    private
      CountTeams: integer;
      CountPlayer: array [0..2] of integer;

      SelectTeams:     cardinal;
      SelectPlayers: array [0..2] of cardinal;
      FCachedSetupValid: boolean;
      FCachedTeamNames: array[0..Party_Teams_Max-1] of UTF8String;
      FCachedPlayerNames: array[0..Party_Teams_Max-1, 0..Party_Players_Max-1] of UTF8String;
      DocumentUI: TDocumentUI;
      DocumentNames: array[0..Party_Teams_Max * (Party_Players_Max + 1)-1] of TNameEntryState;
      DocumentInteraction: integer;
      function GetSetupName(Index: integer): UTF8String;
      procedure SetSetupName(Index: integer; const Value: UTF8String);
      function DocumentNameIndex(Index: integer): integer;
      function DocumentFieldVisible(Index: integer): boolean;
      procedure FocusDocumentField(const Target: UTF8String);
      procedure SyncDocument;
      function DocumentInput(Key: cardinal; CharCode: UCS4Char): boolean;
    public
      Team1Name: cardinal;
      Player1Name: cardinal;
      Player2Name: cardinal;
      Player3Name: cardinal;
      Player4Name: cardinal;

      Team2Name: cardinal;
      Player5Name: cardinal;
      Player6Name: cardinal;
      Player7Name: cardinal;
      Player8Name: cardinal;

      Team3Name: cardinal;
      Player9Name: cardinal;
      Player10Name: cardinal;
      Player11Name: cardinal;
      Player12Name: cardinal;

      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      procedure OnShow; override;
      procedure OnHide; override;
      
      function NoRepeatColors(ColorP:integer; Interaction:integer; Pos:integer):integer;
      procedure TeamColorButton(K: integer; Interact: integer);
      procedure ShuffleNames(var PlayerNames: array of UTF8String);

      procedure UpdateInterface;
      procedure UpdateParty;
      procedure CacheCurrentSetup;
      procedure RestoreCachedSetup;
      procedure SaveCurrentSetup;

  end;

const
  uiPartyPlayersRole = 'party-players';
  uiPartyPlayersData = 'partyPlayers';
  uiPartyPlayersPrevious = 'party.players.previous';
  uiPartyPlayersNext = 'party.players.next';
  uiPartyPlayersActivate = 'party.players.activate';
  uiPartyPlayersContinue = 'party.players.continue';
  ID='ID_031';   //for help system

implementation

uses
  UAvatars,
  UGraphic,
  UHelp,
  UIni,
  ULanguage,
  ULog,
  UMain,
  UScreenPartyOptions,
  USkins,
  UUnicodeUtils,
  Math;

var
  Num: array[0..2] of integer;

function IsDefaultPlayerName(const Name: UTF8String; Player: integer): boolean;
begin
  Result :=
    (Name = 'Player' + IntToStr(Player)) or
    (Name = 'Player ' + IntToStr(Player)) or
    (Name = IPlayerTranslated[Player - 1]) or
    (Name = ULanguage.Language.Translate('OPTION_VALUE_PLAYER') + IntToStr(Player)) or
    (Name = ULanguage.Language.Translate('OPTION_VALUE_PLAYER') + ' ' + IntToStr(Player));
end;

function IsDefaultTeamName(const Name: UTF8String; Team: integer): boolean;
begin
  Result :=
    (Name = 'Team' + IntToStr(Team)) or
    (Name = 'Team ' + IntToStr(Team)) or
    (Name = ITeamTranslated[Team - 1]) or
    (Name = ULanguage.Language.Translate('OPTION_VALUE_TEAM') + IntToStr(Team)) or
    (Name = ULanguage.Language.Translate('OPTION_VALUE_TEAM') + ' ' + IntToStr(Team));
end;

function TScreenPartyPlayer.GetSetupName(Index: integer): UTF8String;
begin
  if DocumentUI <> nil then Result := DocumentNames[Index].Value
  else Result := Button[Index].Text[0].Text;
end;

procedure TScreenPartyPlayer.SetSetupName(Index: integer; const Value: UTF8String);
begin
  if DocumentUI <> nil then DocumentNames[Index].Assign(Value)
  else Button[Index].Text[0].Text := Value;
end;

function TScreenPartyPlayer.DocumentNameIndex(Index: integer): integer;
var Team, Offset: integer;
begin
  Result := -1;
  if (Index < 1) or (Index > Party_Teams_Max * (Party_Players_Max + 2)) then Exit;
  Team := (Index - 1) div (Party_Players_Max + 2);
  Offset := (Index - 1) mod (Party_Players_Max + 2);
  if Offset = 0 then Result := Team * (Party_Players_Max + 1)
  else if Offset >= 2 then Result := Team * (Party_Players_Max + 1) + Offset - 1;
end;

function TScreenPartyPlayer.DocumentFieldVisible(Index: integer): boolean;
var Team, Offset: integer;
begin
  Result := Index = 0;
  if (Index < 1) or (Index > Party_Teams_Max * (Party_Players_Max + 2)) then Exit;
  Team := (Index - 1) div (Party_Players_Max + 2);
  Offset := (Index - 1) mod (Party_Players_Max + 2);
  Result := (Team < CountTeams + 2) and ((Offset < 2) or (Offset - 2 <= CountPlayer[Team]));
end;

procedure TScreenPartyPlayer.FocusDocumentField(const Target: UTF8String);
var Index, NameIndex: integer;
begin
  if not TryStrToInt(Target, Index) or not DocumentFieldVisible(Index) or (Index = DocumentInteraction) then Exit;
  NameIndex := DocumentNameIndex(DocumentInteraction);
  if NameIndex >= 0 then DocumentNames[NameIndex].Finish;
  DocumentInteraction := Index;
  SetTextInput(DocumentNameIndex(Index) >= 0);
end;

function TScreenPartyPlayer.DocumentInput(Key: cardinal; CharCode: UCS4Char): boolean;
var NameIndex, TemplateIndex, Team, Offset, I, J, Count, Direction: integer;
  Modifiers: word;
  RandomNames: array of UTF8String;
begin
  Result := true;
  Modifiers := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT + KMOD_RALT);
  NameIndex := DocumentNameIndex(DocumentInteraction);
  if NameIndex >= 0 then
  begin
    if (Key = SDLK_ESCAPE) and DocumentNames[NameIndex].Cancel then Exit;
    if (Key = SDLK_RETURN) and DocumentNames[NameIndex].Accept then Exit;
    if IsPrintableChar(CharCode) then
    begin
      DocumentNames[NameIndex].TypeText(UCS4ToUTF8String(CharCode));
      if NameIndex mod (Party_Players_Max + 1) = 0 then
        DocumentNames[NameIndex].Suggest(Ini.RecentTeamNames, Theme.NameSuggestionAlpha > 0)
      else DocumentNames[NameIndex].Suggest(Ini.RecentNames, Theme.NameSuggestionAlpha > 0);
      Exit;
    end;
    if Key = SDLK_BACKSPACE then
    begin
      DocumentNames[NameIndex].Backspace;
      if NameIndex mod (Party_Players_Max + 1) = 0 then
        DocumentNames[NameIndex].Suggest(Ini.RecentTeamNames, Theme.NameSuggestionAlpha > 0)
      else DocumentNames[NameIndex].Suggest(Ini.RecentNames, Theme.NameSuggestionAlpha > 0);
      Exit;
    end;
    TemplateIndex := GetNameTemplateIndexFromKey(Key);
    if (TemplateIndex >= 0) and (TemplateIndex <= High(Ini.NameTemplate)) then
    begin
      if (Modifiers = KMOD_LSHIFT) or (Modifiers = KMOD_RSHIFT) or (Modifiers = KMOD_LALT) then
        Ini.NameTemplate[TemplateIndex] := GetSetupName(NameIndex)
      else SetSetupName(NameIndex, Ini.NameTemplate[TemplateIndex]);
      Exit;
    end;
  end;
  case Key of
    SDLK_UP, SDLK_DOWN:
      if (DocumentInteraction > 0) and (((DocumentInteraction - 1) mod (Party_Players_Max + 2)) = 0) and (Modifiers = KMOD_LCTRL) then
      begin
        Team := (DocumentInteraction - 1) div (Party_Players_Max + 2);
        if Key = SDLK_UP then Direction := 1 else Direction := -1;
        Num[Team] := NoRepeatColors(Num[Team] + Direction, Team, Direction);
      end
      else
      begin
        if Key = SDLK_UP then DocumentUI.Key(uiKeyPrevious) else DocumentUI.Key(uiKeyNext);
        FocusDocumentField(DocumentUI.FocusedTarget);
      end;
    SDLK_LEFT, SDLK_RIGHT:
      if NameIndex < 0 then
      begin
        if Key = SDLK_RIGHT then Direction := 1 else Direction := -1;
        AudioPlayback.PlaySound(SoundLib.Option);
        if DocumentInteraction = 0 then
        begin
          CountTeams := EnsureRange(CountTeams + Direction, 0, Party_Teams_Max - 2);
          Num[2] := NoRepeatColors(Num[2], 2, Direction);
        end
        else
        begin
          Team := (DocumentInteraction - 1) div (Party_Players_Max + 2);
          CountPlayer[Team] := EnsureRange(CountPlayer[Team] + Direction, 0, Party_Players_Max - 1);
        end;
      end;
    SDLK_RETURN: UpdateParty;
    SDLK_ESCAPE:
      begin
        SaveCurrentSetup;
        Ini.SaveNames;
        FadeTo(@ScreenPartyOptions, SoundLib.Back);
      end;
    SDLK_TAB: ScreenPopupHelp.ShowPopup;
    SDLK_Q: if NameIndex < 0 then Result := false;
    SDLK_R:
      if Modifiers = KMOD_LCTRL then
      begin
        AudioPlayback.PlaySound(SoundLib.Option);
        SetLength(RandomNames, Party_Teams_Max * Party_Players_Max);
        Count := 0;
        for I := 0 to CountTeams + 1 do
          for J := 0 to CountPlayer[I] do
          begin
            RandomNames[Count] := GetSetupName(I * (Party_Players_Max + 1) + J + 1); Inc(Count);
          end;
        SetLength(RandomNames, Count);
        ShuffleNames(RandomNames);
        Dec(Count);
        for I := 0 to CountTeams + 1 do
          for J := 0 to CountPlayer[I] do
          begin
            SetSetupName(I * (Party_Players_Max + 1) + J + 1, RandomNames[Count]); Dec(Count);
          end;
      end;
  end;
end;

procedure TScreenPartyPlayer.SyncDocument;
var Team, Player, Index, Field: integer; Prefix, Child: UTF8String;
  function ColorText(const Color: TRGB): UTF8String;
  begin
    Result := '#' + IntToHex(EnsureRange(Round(Color.R * 255), 0, 255), 2) +
      IntToHex(EnsureRange(Round(Color.G * 255), 0, 255), 2) + IntToHex(EnsureRange(Round(Color.B * 255), 0, 255), 2);
  end;
begin
  DocumentUI.SetModel(uiPartyPlayersData + '.count', IntToStr(CountTeams + 2), 1);
  DocumentUI.SetModel(uiPartyPlayersData + '.focus', IntToStr(DocumentInteraction), 1);
  DocumentUI.SetModel(uiPartyPlayersData + '.previous', IntToStr(Ord(CountTeams > 0)), 2);
  DocumentUI.SetModel(uiPartyPlayersData + '.next', IntToStr(Ord(CountTeams < Party_Teams_Max - 2)), 2);
  DocumentUI.SetArray(uiPartyPlayersData + '.teams', Party_Teams_Max);
  for Team := 0 to Party_Teams_Max - 1 do
  begin
    Prefix := uiPartyPlayersData + '.teams[' + IntToStr(Team) + '].';
    Index := Team * (Party_Players_Max + 1);
    Field := Team * (Party_Players_Max + 2) + 1;
    DocumentUI.SetModel(Prefix + 'id', IntToStr(Team), 1);
    DocumentUI.SetModel(Prefix + 'visible', IntToStr(Ord(Team < CountTeams + 2)), 2);
    DocumentUI.SetModel(Prefix + 'nameId', IntToStr(Field), 1);
    DocumentUI.SetModel(Prefix + 'countId', IntToStr(Field + 1), 1);
    DocumentUI.SetModel(Prefix + 'name', DocumentNames[Index].Value);
    DocumentUI.SetModel(Prefix + 'suffix', DocumentNames[Index].Suffix);
    DocumentUI.SetModel(Prefix + 'count', IntToStr(CountPlayer[Team] + 1), 1);
    DocumentUI.SetModel(Prefix + 'previous', IntToStr(Ord(CountPlayer[Team] > 0)), 2);
    DocumentUI.SetModel(Prefix + 'next', IntToStr(Ord(CountPlayer[Team] < Party_Players_Max - 1)), 2);
    DocumentUI.SetModel(Prefix + 'color', ColorText(GetPlayerColor(Num[Team])));
    DocumentUI.SetModel(Prefix + 'light', ColorText(GetPlayerLightColor(Num[Team])));
    DocumentUI.SetArray(Prefix + 'players', Party_Players_Max);
    for Player := 0 to Party_Players_Max - 1 do
    begin
      Child := Prefix + 'players[' + IntToStr(Player) + '].';
      DocumentUI.SetModel(Child + 'id', IntToStr(Field + 2 + Player), 1);
      DocumentUI.SetModel(Child + 'visible', IntToStr(Ord(Player <= CountPlayer[Team])), 2);
      DocumentUI.SetModel(Child + 'name', DocumentNames[Index + Player + 1].Value);
      DocumentUI.SetModel(Child + 'suffix', DocumentNames[Index + Player + 1].Suffix);
    end;
  end;
  DocumentUI.Focus('party-player-' + IntToStr(DocumentInteraction));
end;

destructor TScreenPartyPlayer.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenPartyPlayer.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenPartyPlayer.DrawFG: boolean;
begin
  if DocumentUI <> nil then begin SyncDocument; Exit(DocumentUI.Draw(false, true)); end;
  Result := inherited;
end;

procedure TScreenPartyPlayer.CacheCurrentSetup;
var
  Team, Player: integer;
  TeamName, PlayerName: UTF8String;
begin
  for Team := 0 to Party_Teams_Max - 1 do
  begin
    TeamName := GetSetupName(Team * 5);
    if IsDefaultTeamName(TeamName, Team + 1) then
      FCachedTeamNames[Team] := 'Team' + IntToStr(Team + 1)
    else
      FCachedTeamNames[Team] := TeamName;

    for Player := 0 to Party_Players_Max - 1 do
    begin
      PlayerName := GetSetupName(Team * 5 + Player + 1);
      if IsDefaultPlayerName(PlayerName, Team * Party_Players_Max + Player + 1) then
        FCachedPlayerNames[Team, Player] :=
          'Player' + IntToStr(Team * Party_Players_Max + Player + 1)
      else
        FCachedPlayerNames[Team, Player] := PlayerName;
    end;
  end;
  FCachedSetupValid := true;
end;

procedure TScreenPartyPlayer.RestoreCachedSetup;
var
  Team, Player: integer;
  TeamName, PlayerName: UTF8String;
begin
  for Team := 0 to Party_Teams_Max - 1 do
  begin
    TeamName := FCachedTeamNames[Team];
    if IsDefaultTeamName(TeamName, Team + 1) then
      SetSetupName(Team * 5, ITeamTranslated[Team])
    else
      SetSetupName(Team * 5, TeamName);

    for Player := 0 to Party_Players_Max - 1 do
    begin
      PlayerName := FCachedPlayerNames[Team, Player];
      if IsDefaultPlayerName(PlayerName, Team * Party_Players_Max + Player + 1) then
        SetSetupName(Team * 5 + Player + 1, IPlayerTranslated[Team * Party_Players_Max + Player])
      else
        SetSetupName(Team * 5 + Player + 1, PlayerName);
    end;
  end;
end;

procedure TScreenPartyPlayer.SaveCurrentSetup;
var
  I: integer;
begin
  // Save team names
  for I := 0 to 2 do
  begin
    if IsDefaultTeamName(GetSetupName(I * 5), I + 1) then
      Ini.NameTeam[I] := 'Team' + IntToStr(I + 1)
    else
      Ini.NameTeam[I] := GetSetupName(I * 5);
  end;

  // Save player names
  for I := 0 to 3 do
  begin
    if IsDefaultPlayerName(GetSetupName(I + 1), I + 1) then
      Ini.Name[I] := 'Player' + IntToStr(I + 1)
    else
      Ini.Name[I] := GetSetupName(I + 1);

    if IsDefaultPlayerName(GetSetupName(I + 6), I + 5) then
      Ini.Name[I + 4] := 'Player' + IntToStr(I + 5)
    else
      Ini.Name[I + 4] := GetSetupName(I + 6);

    if IsDefaultPlayerName(GetSetupName(I + 11), I + 9) then
      Ini.Name[I + 8] := 'Player' + IntToStr(I + 9)
    else
      Ini.Name[I + 8] := GetSetupName(I + 11);
  end;
end;

procedure TScreenPartyPlayer.UpdateInterface;
  var
    I: integer;
    Btn: integer;
begin
  if DocumentUI <> nil then Exit;
  SelectsS[SelectPlayers[2]].Visible := (CountTeams = 1);

  Btn := 0;
  for I := 0 to 2 do
  begin
    TeamColorButton(Num[I], I);

    if (CountTeams + 1 >= I) then
    begin
      Button[Btn + 0].Visible := true;
      Button[Btn + 1].Visible := (CountPlayer[I] + 1 >= 1);
      Button[Btn + 2].Visible := (CountPlayer[I] + 1 >= 2);
      Button[Btn + 3].Visible := (CountPlayer[I] + 1 >= 3);
      Button[Btn + 4].Visible := (CountPlayer[I] + 1 >= 4);
    end
    else
    begin
      Button[Btn + 0].Visible := false;
      Button[Btn + 1].Visible := false;
      Button[Btn + 2].Visible := false;
      Button[Btn + 3].Visible := false;
      Button[Btn + 4].Visible := false;
    end;
    Inc(Btn, 5);
  end;
end;

procedure TScreenPartyPlayer.UpdateParty;
var
    I, J: integer;
    Col: TRGB;
begin

  if (DocumentUI <> nil) and (DocumentNameIndex(DocumentInteraction) >= 0) then
    DocumentNames[DocumentNameIndex(DocumentInteraction)].Finish;
  CacheCurrentSetup;

  // add teams to party

  for I := 0 to CountTeams + 1 do
  begin
    Ini.SingColor[I] := Num[I];
    Ini.TeamColor[I] := Num[I];
    
    Party.AddTeam(GetSetupName(I * 5));

    for J := 0 to CountPlayer[I] do
      Party.AddPlayer(I, GetSetupName(I * 5 + 1 + J));

    // no avatar on Party
    AvatarPlayerTextures[I + 1] := DefaultAvatarTexture(I);

    Col := GetPlayerColor(Num[I]);

    if Skin.ColorizeDefaultAvatars then
    begin
      AvatarPlayerTextures[I + 1].ColR := Col.R;
      AvatarPlayerTextures[I + 1].ColG := Col.G;
      AvatarPlayerTextures[I + 1].ColB := Col.B;
    end;
  end;


  // MOD Colors
  Ini.SaveTeamColors;
  LoadTeamsColors;
  Theme.ThemePartyLoad;
  ScreenSong.ColorizeJokers;

  // Reload ScreenSing and ScreenScore because of player colors
  // TODO: do this better
  freeandnil(ScreenSing);
  freeandnil(ScreenPartyNewRound);
  freeandnil(ScreenPartyWin);
  freeandnil(ScreenPartyScore);

  Party.bPartyGame := true;
  PlayersPlay := Length(Party.Teams);

  ScreenSing := TScreenSingController.Create;
  ScreenPartyNewRound := TScreenPartyNewRound.Create;
  ScreenPartyWin := TScreenPartyWin.Create;
  ScreenPartyScore := TScreenPartyScore.Create;

  if (Party.ModesAvailable) then
  begin //mode for current playersetup available
    for I := CountTeams + 1 downto 0 do
    begin
      for J := CountPlayer[I] downto 0 do
        Ini.RememberUsedNames([GetSetupName(I * 5 + 1 + J)]);
      Ini.RememberUsedTeamNames([GetSetupName(I * 5)]);
    end;
    SaveCurrentSetup;
    Ini.SaveNames;
    FadeTo(@ScreenPartyRounds, SoundLib.Start);
  end
  else
  begin
    // no mode available for current player setup
    ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_MODES_FOR_CURRENT_SETUP'));
    Party.Clear;
  end;
end;

function TScreenPartyPlayer.ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean;
begin
  if DocumentUI <> nil then
  begin
    SuppressKey := (DocumentNameIndex(DocumentInteraction) >= 0) and (GetNameTemplateIndexFromKey(PressedKey) <> -1);
    Exit((GetNameTemplateIndexFromKey(PressedKey) = -1) or (DocumentNameIndex(DocumentInteraction) >= 0));
  end;
  Result := inherited;
  // only suppress special keys for now
  if GetNameTemplateIndexFromKey(PressedKey) <> -1 then
    if (Button[Interactions[Interaction].Num].Selected) then
      SuppressKey := true
    else
      Result := false;
end;

function TScreenPartyPlayer.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
  var
    SDL_ModState:  word;
    Team: integer;
    I, J, count: integer;
    randomNames: array of UTF8String; // new for randomizing names
  procedure IntNext;
  begin
    repeat
      InteractNext;
    until ((Interactions[Interaction].Typ = iSelectS) and
      SelectsS[Interactions[Interaction].Num].Visible) or
      (Button[Interactions[Interaction].Num].Visible);
    SetTextInput(Interactions[Interaction].Typ = iButton);
  end;
  procedure IntPrev;
  begin
    repeat
      InteractPrev;
    until ((Interactions[Interaction].Typ = iSelectS) and
      SelectsS[Interactions[Interaction].Num].Visible) or
      (Button[Interactions[Interaction].Num].Visible);
    SetTextInput(Interactions[Interaction].Typ = iButton);
  end;
  procedure HandleNameTemplate(const index: integer);
  var
    isAlternate: boolean;
  begin
    isAlternate := (SDL_ModState = KMOD_LSHIFT) or (SDL_ModState = KMOD_RSHIFT);
    isAlternate := isAlternate or (SDL_ModState = KMOD_LALT); // legacy key combination

    if isAlternate then Ini.NameTemplate[index] := GetSetupName(Interactions[Interaction].Num)
    else SetSetupName(Interactions[Interaction].Num, Ini.NameTemplate[index]);
  end;
  procedure HandleTemplateHotkey;
  var
    TemplateIndex: integer;
  begin
    TemplateIndex := GetNameTemplateIndexFromKey(PressedKey);
    if (TemplateIndex >= 0) and (TemplateIndex <= High(Ini.NameTemplate)) then
      HandleNameTemplate(TemplateIndex);
  end;
begin
  Result := true;
  if not PressedDown then Exit;
  if DocumentUI <> nil then Exit(DocumentInput(PressedKey, CharCode));
  if HandleNameSuggestionKey(PressedKey) then Exit;

  if (PressedDown) then
    SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
        + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT)
  else
    SDL_ModState := 0;

  // Key Down
  // check normal keys
  if (Interactions[Interaction].Typ = iButton) then
  begin

    // check normal keys
    if (IsPrintableChar(CharCode)) then
    begin
      Button[Interactions[Interaction].Num].Text[0].TypeNameCharacter(UCS4ToUTF8String(CharCode));
      Exit;
    end;

    // check special keys
    case PressedKey of
      SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6,
      SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11, SDLK_F12:
        HandleTemplateHotkey;
      SDLK_BACKSPACE:
        begin
          Button[Interactions[Interaction].Num].Text[0].DeleteNameCharacter;
        end;
    end;
  end
  else
  begin
    // check normal keys
    case PressedKey of
      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;
  end;

  case PressedKey of
    SDLK_ESCAPE:
      begin
        SaveCurrentSetup;
        Ini.SaveNames;
        AudioPlayback.PlaySound(SoundLib.Back);
        FadeTo(@ScreenPartyOptions);
      end;

    SDLK_TAB:
      begin
        ScreenPopupHelp.ShowPopup();
      end;

    SDLK_RETURN: UpdateParty;

    // Up and Down could be done at the same time,
    // but I don't want to declare variables inside
    // functions like this one, called so many times
    SDLK_DOWN:
      begin
        if (Interaction in [1, 7, 13]) and (SDL_ModState = KMOD_LCTRL) then
        begin

          case Interaction of
            1: Team := 0;
            7: Team := 1;
            13: Team := 2;
          end;

          Num[Team] := Num[Team] - 1;
          Num[Team] := NoRepeatColors(Num[Team], Team, -1);
          TeamColorButton(Num[Team], Team);
        end
        else
          IntNext;
      end;
    SDLK_UP:
      begin
        if (Interaction in [1, 7, 13]) and (SDL_ModState = KMOD_LCTRL) then
        begin

          case Interaction of
            1: Team := 0;
            7: Team := 1;
            13: Team := 2;
          end;

          //SetSetupName(Team * 5, 'BUTTON ' + IntTostr(Team));

          Num[Team] := Num[Team] + 1;
          Num[Team] := NoRepeatColors(Num[Team], Team, 1);
          TeamColorButton(Num[Team], Team);
        end
        else
          IntPrev;
      end;
    SDLK_RIGHT:
      begin
        if (Interaction in [0,2,8,14]) then
        begin
          AudioPlayback.PlaySound(SoundLib.Option);
          InteractInc;
          UpdateInterface;

          if (Interaction = 0) then
          begin
            Num[2] := NoRepeatColors(Num[2], 2, 1);
            TeamColorButton(Num[2], 2);
          end;

        //CORRECT
        for I := 0 to 3 do
          IntNext;

        for I := 0 to 3 do
          IntPrev;

        end;
      end;
    SDLK_LEFT:
      begin
        if (Interaction in [0,2,8,14]) then
        begin
          AudioPlayback.PlaySound(SoundLib.Option);
          InteractDec;
          UpdateInterface;
        end;

        //CORRECT
        for I := 0 to 3 do
          IntNext;

        for I := 0 to 3 do
          IntPrev;

      end;
    SDLK_R:
      begin
        if (SDL_ModState = KMOD_LCTRL) then
        begin
          AudioPlayback.PlaySound(SoundLib.Option);
          //InteractDec;
          //UpdateInterface;

          count := 0;
          SetLength(randomNames, 12);

          // collect all player names
          for I := 0 to self.CountTeams+1 do
            for J := 0 to CountPlayer[I] do
            begin
              randomNames[count] := GetSetupName(5*I+J+1);
              inc(count);
            end;

          // shuffle player names
          SetLength(randomNames, count);
          ShuffleNames(randomNames);

          // set shuffled player names
          dec(count);
          for I := 0 to self.CountTeams+1 do
            for J := 0 to CountPlayer[I] do
            begin
              SetSetupName(5*I+J+1, randomNames[count]);
              dec(count);
            end;
        end;
      end;
  end;
end;

function TScreenPartyPlayer.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action: UTF8String;
begin
  if DocumentUI <> nil then
  begin
    if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then Exit(DocumentInput(SDLK_ESCAPE, 0));
    if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown) else DocumentUI.Mouse(X, Y);
    FocusDocumentField(DocumentUI.FocusedTarget);
    Action := DocumentUI.TakeAction;
    if Action = uiPartyPlayersPrevious then begin FocusDocumentField(DocumentUI.ActionTarget); DocumentInput(SDLK_LEFT, 0); end
    else if Action = uiPartyPlayersNext then begin FocusDocumentField(DocumentUI.ActionTarget); DocumentInput(SDLK_RIGHT, 0); end
    else if Action = uiPartyPlayersActivate then begin FocusDocumentField(DocumentUI.ActionTarget); DocumentInput(SDLK_RETURN, 0); end
    else if Action = uiPartyPlayersContinue then UpdateParty
    else if Action = uiNavigationBack then DocumentInput(SDLK_ESCAPE, 0);
    Exit(true);
  end;
  Result := true;
  inherited ParseMouse(MouseButton, BtnDown, X, Y);
  SetTextInput(Interactions[Interaction].Typ = iButton);
end;

constructor TScreenPartyPlayer.Create;
var
  ButtonID: integer;
  TeamOptions: TUTF8StringArray;
  PlayerOptions: TUTF8StringArray;
begin
  inherited Create;

  DocumentUI := TDocumentUI.Open(uiPartyPlayersRole);
  if DocumentUI <> nil then Exit;

  LoadFromTheme(Theme.PartyPlayer);

  TeamOptions := CreateNumericOptionArray(2, 3);
  PlayerOptions := CreateNumericOptionArray(1, 4);

  Theme.PartyPlayer.SelectTeams.oneItemOnly := true;
  Theme.PartyPlayer.SelectTeams.showArrows := true;
  SelectTeams     := AddSelectSlide(Theme.PartyPlayer.SelectTeams, CountTeams, TeamOptions);

  Team1Name := AddButton(Theme.PartyPlayer.Team1Name);
  Button[Team1Name].Text[0].Writable := true;
  Button[Team1Name].Text[0].NameEntryField := true;
  Button[Team1Name].Text[0].TeamNameField := true;

  Theme.PartyPlayer.SelectPlayers1.oneItemOnly := true;
  Theme.PartyPlayer.SelectPlayers1.showArrows := true;
  SelectPlayers[0]  := AddSelectSlide(Theme.PartyPlayer.SelectPlayers1, CountPlayer[0], PlayerOptions);

  ButtonID := AddButton(Theme.PartyPlayer.Player1Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player2Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player3Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player4Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  Team2Name := AddButton(Theme.PartyPlayer.Team2Name);
  Button[Team2Name].Text[0].Writable := true;
  Button[Team2Name].Text[0].NameEntryField := true;
  Button[Team2Name].Text[0].TeamNameField := true;

  Theme.PartyPlayer.SelectPlayers2.oneItemOnly := true;
  Theme.PartyPlayer.SelectPlayers2.showArrows := true;
  SelectPlayers[1]  := AddSelectSlide(Theme.PartyPlayer.SelectPlayers2, CountPlayer[1], PlayerOptions);

  ButtonID := AddButton(Theme.PartyPlayer.Player5Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player6Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player7Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player8Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  Team3Name := AddButton(Theme.PartyPlayer.Team3Name);
  Button[Team3Name].Text[0].Writable := true;
  Button[Team3Name].Text[0].NameEntryField := true;
  Button[Team3Name].Text[0].TeamNameField := true;

  Theme.PartyPlayer.SelectPlayers3.oneItemOnly := true;
  Theme.PartyPlayer.SelectPlayers3.showArrows := true;
  SelectPlayers[2]  := AddSelectSlide(Theme.PartyPlayer.SelectPlayers3, CountPlayer[2], PlayerOptions);

  ButtonID := AddButton(Theme.PartyPlayer.Player9Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player10Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player11Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  ButtonID := AddButton(Theme.PartyPlayer.Player12Name);
  Button[ButtonID].Text[0].Writable := true;
  Button[ButtonID].Text[0].NameEntryField := true;

  Button[Team2Name].Text[0].Selected  := true;

  Interaction := 0;

  //Clear Selects
  CountTeams := 0;
  CountPlayer[0] := 0;
  CountPlayer[1] := 0;
  CountPlayer[2] := 0;
  FCachedSetupValid := false;
end;

procedure TScreenPartyPlayer.OnHide;
begin
  StopTextInput;
  inherited;
end;

procedure TScreenPartyPlayer.OnShow;
var
  I:    integer;
begin
  if DocumentUI = nil then inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenPartyPlayer');

  if FCachedSetupValid then
  begin
    RestoreCachedSetup;
  end
  else
  begin
    for I := 0 to 2 do
      Num[I] := NoRepeatColors(Ini.TeamColor[I], I, 1);

    // Templates for Names Mod
    for I := 1 to 4 do
    begin
      if IsDefaultPlayerName(Ini.Name[I-1], I) then
        SetSetupName(I, IPlayerTranslated[I-1])
      else
        SetSetupName(I, Ini.Name[I-1]);
    end;

    for I := 6 to 9 do
    begin
      if IsDefaultPlayerName(Ini.Name[I-2], I-1) then
        SetSetupName(I, IPlayerTranslated[I-2])
      else
        SetSetupName(I, Ini.Name[I-2]);
    end;

    for I := 11 to 14 do
    begin
      if IsDefaultPlayerName(Ini.Name[I-3], I-2) then
        SetSetupName(I, IPlayerTranslated[I-3])
      else
        SetSetupName(I, Ini.Name[I-3]);
    end;

    for I := 0 to 2 do
    begin
      if IsDefaultTeamName(Ini.NameTeam[I], I + 1) then
        SetSetupName(I * 5, ITeamTranslated[I])
      else
        SetSetupName(I * 5, Ini.NameTeam[I]);
    end;
    // Templates for Names Mod end
  end;

  Party.Clear;

  UpdateInterface;
  if DocumentUI <> nil then
  begin
    if not DocumentFieldVisible(DocumentInteraction) then DocumentInteraction := 0;
    SyncDocument;
    SetTextInput(DocumentNameIndex(DocumentInteraction) >= 0);
  end
  else SetTextInput((Interaction >= 0) and (Interaction <= High(Interactions)) and
      (Interactions[Interaction].Typ = iButton));
end;

function TScreenPartyPlayer.NoRepeatColors(ColorP:integer; Interaction:integer; Pos:integer):integer;
var
  Z:integer;
begin

  if (ColorP >= 10) then
    ColorP := NoRepeatColors(1, Interaction, Pos);

  if (ColorP <= 0) then
    ColorP := NoRepeatColors(9, Interaction, Pos);

  for Z := 0 to CountTeams + 1 do
  begin
    if Z <> Interaction then
    begin
     if (Num[Z] = ColorP) then
       ColorP := NoRepeatColors(ColorP + Pos, Interaction, Pos)
    end;
  end;

  Result := ColorP;

end;

procedure TScreenPartyPlayer.TeamColorButton(K: integer; Interact: integer);
var
  Col, DesCol: TRGB;
  I: integer;
begin

  if DocumentUI <> nil then Exit;
  Col := GetPlayerLightColor(K);
  DesCol := GetPlayerColor(K);

  for I := 0 to 4 do
  begin
    Button[Interact * 5 + I].SelectColR:= Col.R;
    Button[Interact * 5 + I].SelectColG:= Col.G;
    Button[Interact * 5 + I].SelectColB:= Col.B;

    Button[Interact * 5 + I].DeselectColR:= DesCol.R;
    Button[Interact * 5 + I].DeselectColG:= DesCol.G;
    Button[Interact * 5 + I].DeselectColB:= DesCol.B;
  end;

  SelectsS[Interact + 1].ColR := Col.R;
  SelectsS[Interact + 1].ColG := Col.G;
  SelectsS[Interact + 1].ColB := Col.B;

  SelectsS[Interact + 1].DColR := DesCol.R;
  SelectsS[Interact + 1].DColG := DesCol.G;
  SelectsS[Interact + 1].DColB := DesCol.B;

  SelectsS[Interact + 1].SBGColR := Col.R;
  SelectsS[Interact + 1].SBGColG := Col.G;
  SelectsS[Interact + 1].SBGColB := Col.B;

  SelectsS[Interact + 1].SBGDColR := DesCol.R;
  SelectsS[Interact + 1].SBGDColG := DesCol.G;
  SelectsS[Interact + 1].SBGDColB := DesCol.B;

  //Interaction := Interact;

  //CORRECT
  for I := 0 to 15 do
    InteractNext;

  for I := 0 to 15 do
    InteractPrev;

end;

// random permutation of player names according to Fisher-Yates
procedure TScreenPartyPlayer.ShuffleNames(var PlayerNames: array of UTF8String);
var
  I, J: Integer;
  tmp: UTF8String;
begin
  for I := Low(PlayerNames) to High(PlayerNames) do begin
    J := I + Random(Length(PlayerNames) - I + Low(PlayerNames));
    tmp := PlayerNames[J];
    PlayerNames[J] := PlayerNames[I];
    PlayerNames[I] := tmp;
  end;
end;

end.
