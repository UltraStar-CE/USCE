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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenPartyTournmentPlayer.pas $
 * $Id: $
 *}

unit UScreenPartyTournamentPlayer;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UDocumentUI,
  URecentNames,
  UFiles,
  UMenu,
  UMusic,
  UPartyTournament,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenPartyTournamentPlayer = class(TMenu)
    private
      SelectPlayers: cardinal;

      FRestoreNames: boolean;
      DocumentUI: TDocumentUI;
      DocumentNames: array[0..15] of TNameEntryState;
      DocumentField: integer;
      function ParticipantName(Index: integer): UTF8String;
      procedure AssignParticipantName(Index: integer; const Value: UTF8String);
      procedure ContinueTournament;
      procedure FocusDocumentField(const Target: UTF8String);
      procedure SyncDocument;
      function DocumentInput(Key: cardinal; CharCode: UCS4Char): boolean;
      procedure UpdateInterface;
      procedure UpdatePartyTournament;
    public
      PlayersName: array of UTF8String;
      CountPlayer:   integer;

      Player1Name: cardinal;
      Player2Name: cardinal;
      Player3Name: cardinal;
      Player4Name: cardinal;
      Player5Name: cardinal;
      Player6Name: cardinal;
      Player7Name: cardinal;
      Player8Name: cardinal;
      Player9Name: cardinal;
      Player10Name: cardinal;
      Player11Name: cardinal;
      Player12Name: cardinal;
      Player13Name: cardinal;
      Player14Name: cardinal;
      Player15Name: cardinal;
      Player16Name: cardinal;

      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      procedure OnShow; override;
      procedure OnHide; override;
  end;

const
  ID='ID_036';   //for help system

implementation

uses
  UGraphic,
  UHelp,
  ULog,
  UMain,
  UIni,
  UUnicodeUtils,
  UScreenPartyOptions,
  ULanguage, Math;

function TScreenPartyTournamentPlayer.ParticipantName(Index: integer): UTF8String;
begin
  if DocumentUI <> nil then Result := DocumentNames[Index].Value
  else Result := Button[Index].Text[0].Text;
end;

procedure TScreenPartyTournamentPlayer.AssignParticipantName(Index: integer; const Value: UTF8String);
begin
  if DocumentUI <> nil then DocumentNames[Index].Assign(Value)
  else Button[Index].Text[0].Text := Value;
end;

procedure TScreenPartyTournamentPlayer.ContinueTournament;
var I: integer;
begin
  if (DocumentUI <> nil) and (DocumentField >= 0) then DocumentNames[DocumentField].Finish;
  for I := CountPlayer + 1 downto 0 do Ini.RememberUsedNames([ParticipantName(I)]);
  Ini.SaveNames;
  UpdatePartyTournament;
  FRestoreNames := true;
  FadeTo(@ScreenPartyTournamentOptions, SoundLib.Start);
end;

procedure TScreenPartyTournamentPlayer.FocusDocumentField(const Target: UTF8String);
var Index: integer;
begin
  if Target = 'count' then Index := -1
  else if not TryStrToInt(Target, Index) then Exit;
  if (Index < -1) or (Index > CountPlayer + 1) or (Index = DocumentField) then Exit;
  if DocumentField >= 0 then DocumentNames[DocumentField].Finish;
  DocumentField := Index;
  SetTextInput(Index >= 0);
end;

function TScreenPartyTournamentPlayer.DocumentInput(Key: cardinal; CharCode: UCS4Char): boolean;
var TemplateIndex: integer; Modifiers: word;
begin
  Result := true;
  if DocumentField >= 0 then
  begin
    if (Key = SDLK_ESCAPE) and DocumentNames[DocumentField].Cancel then Exit;
    if (Key = SDLK_RETURN) and DocumentNames[DocumentField].Accept then Exit;
    if IsPrintableChar(CharCode) then
    begin
      DocumentNames[DocumentField].TypeText(UCS4ToUTF8String(CharCode));
      DocumentNames[DocumentField].Suggest(Ini.RecentNames, Theme.NameSuggestionAlpha > 0);
      Exit;
    end;
    if Key = SDLK_BACKSPACE then
    begin
      DocumentNames[DocumentField].Backspace;
      DocumentNames[DocumentField].Suggest(Ini.RecentNames, Theme.NameSuggestionAlpha > 0);
      Exit;
    end;
    TemplateIndex := GetNameTemplateIndexFromKey(Key);
    if (TemplateIndex >= 0) and (TemplateIndex <= High(Ini.NameTemplate)) then
    begin
      Modifiers := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT + KMOD_RALT);
      if (Modifiers = KMOD_LSHIFT) or (Modifiers = KMOD_RSHIFT) or (Modifiers = KMOD_LALT) then
        Ini.NameTemplate[TemplateIndex] := ParticipantName(DocumentField)
      else AssignParticipantName(DocumentField, Ini.NameTemplate[TemplateIndex]);
      Exit;
    end;
  end;
  case Key of
    SDLK_UP, SDLK_DOWN:
      begin
        if Key = SDLK_UP then DocumentUI.Key(uiKeyPrevious) else DocumentUI.Key(uiKeyNext);
        FocusDocumentField(DocumentUI.FocusedTarget);
      end;
    SDLK_LEFT, SDLK_RIGHT:
      if DocumentField = -1 then
      begin
        AudioPlayback.PlaySound(SoundLib.Option);
        if Key = SDLK_LEFT then CountPlayer := Max(0, CountPlayer - 1)
        else CountPlayer := Min(14, CountPlayer + 1);
      end;
    SDLK_RETURN: ContinueTournament;
    SDLK_ESCAPE:
      begin
        Ini.SaveNames;
        AudioPlayback.PlaySound(SoundLib.Back);
        FadeTo(@ScreenPartyOptions);
      end;
    SDLK_TAB: ScreenPopupHelp.ShowPopup;
    SDLK_Q: if DocumentField = -1 then Result := false;
  end;
end;

procedure TScreenPartyTournamentPlayer.SyncDocument;
var I: integer; Prefix: UTF8String;
begin
  DocumentUI.SetModel('participants.count', IntToStr(CountPlayer + 2), 1);
  DocumentUI.SetModel('participants.focus', IntToStr(DocumentField), 1);
  DocumentUI.SetModel('participants.previousCount', IntToStr(Ord(CountPlayer > 0)), 2);
  DocumentUI.SetModel('participants.nextCount', IntToStr(Ord(CountPlayer < 14)), 2);
  DocumentUI.SetArray('participants.fields', Length(DocumentNames));
  for I := 0 to High(DocumentNames) do
  begin
    Prefix := 'participants.fields[' + IntToStr(I) + '].';
    DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
    DocumentUI.SetModel(Prefix + 'visible', IntToStr(Ord(I < CountPlayer + 2)), 2);
    DocumentUI.SetModel(Prefix + 'value', DocumentNames[I].Value);
    DocumentUI.SetModel(Prefix + 'suffix', DocumentNames[I].Suffix);
  end;
  if DocumentField = -1 then DocumentUI.Focus('participants-count')
  else DocumentUI.Focus('participant-' + IntToStr(DocumentField));
end;

destructor TScreenPartyTournamentPlayer.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenPartyTournamentPlayer.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenPartyTournamentPlayer.DrawFG: boolean;
begin
  if DocumentUI <> nil then begin SyncDocument; Exit(DocumentUI.Draw(false, true)); end;
  Result := inherited;
end;

procedure TScreenPartyTournamentPlayer.UpdateInterface;
var
    I: integer;
begin

  if DocumentUI <> nil then Exit;

  for I := 0 to CountPlayer do
    Button[I + 1].Visible := true;

  for I := CountPlayer + 1 to 14 do
    Button[I + 1].Visible := false;

end;

procedure TScreenPartyTournamentPlayer.UpdatePartyTournament;
var
  I, J, R: integer;
  TMP_PlayersName: array of UTF8String;
  TMP2_PlayersName: array of UTF8String;
begin
  SetLength(PlayersName, CountPlayer + 2);
  SetLength(TMP_PlayersName, CountPlayer + 2);

  for I := 0 to CountPlayer + 1 do
    TMP_PlayersName[I] := ParticipantName(I);

  // random
  for I:= 0 to CountPlayer + 1 do
  begin
    Randomize;
    R := Random(Length(TMP_PlayersName));

    PlayersName[I] := TMP_PlayersName[R];

    // remove
    SetLength(TMP2_PlayersName, 0);
    for J := 0 to High(TMP_PlayersName) do
    begin
      if (R <> J) then
      begin
        SetLength(TMP2_PlayersName, Length(TMP2_PlayersName) + 1);
        TMP2_PlayersName[High(TMP2_PlayersName)] := TMP_PlayersName[J];
      end;
    end;

    // refresh tmp
    SetLength(TMP_PlayersName, Length(TMP2_PlayersName));
    for J := 0 to High(TMP2_PlayersName) do
      TMP_PlayersName[J] := TMP2_PlayersName[J];
  end;

  PartyTournament.PlayersCount := CountPlayer + 2;

end;

function TScreenPartyTournamentPlayer.ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean;
begin
  if DocumentUI <> nil then
  begin
    SuppressKey := (DocumentField >= 0) and (GetNameTemplateIndexFromKey(PressedKey) <> -1);
    Exit((GetNameTemplateIndexFromKey(PressedKey) = -1) or (DocumentField >= 0));
  end;
  Result := inherited;
  // only suppress special keys for now
  if GetNameTemplateIndexFromKey(PressedKey) <> -1 then
    if (Button[Interactions[Interaction].Num].Selected) then
      SuppressKey := true
    else
      Result := false;
end;

function TScreenPartyTournamentPlayer.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
var
  SDL_ModState:  word;
  isAlternate: boolean;
  TemplateIndex: integer;
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
    isAlternate := (SDL_ModState = KMOD_LSHIFT) or (SDL_ModState = KMOD_RSHIFT);
    isAlternate := isAlternate or (SDL_ModState = KMOD_LALT); // legacy key combination
    case PressedKey of
      SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6,
      SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11, SDLK_F12:
        begin
          TemplateIndex := GetNameTemplateIndexFromKey(PressedKey);
          if (TemplateIndex >= 0) and (TemplateIndex <= High(Ini.NameTemplate)) then
            if isAlternate then
              Ini.NameTemplate[TemplateIndex] := Button[Interactions[Interaction].Num].Text[0].Text
            else
              Button[Interactions[Interaction].Num].Text[0].Text := Ini.NameTemplate[TemplateIndex];
        end;
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
        Ini.SaveNames;
        AudioPlayback.PlaySound(SoundLib.Back);
        FadeTo(@ScreenPartyOptions);
      end;

    SDLK_TAB:
      begin
        ScreenPopupHelp.ShowPopup();
      end;

    SDLK_RETURN:
      begin
        ContinueTournament;
      end;
    // Up and Down could be done at the same time,
    // but I don't want to declare variables inside
    // functions like this one, called so many times
    SDLK_DOWN:    IntNext;
    SDLK_UP:      IntPrev;
    SDLK_RIGHT:
      begin
        AudioPlayback.PlaySound(SoundLib.Option);
        InteractInc;

        UpdateInterface;
      end;
    SDLK_LEFT:
      begin
        AudioPlayback.PlaySound(SoundLib.Option);
        InteractDec;

        UpdateInterface;
      end;
  end;
end;

function TScreenPartyTournamentPlayer.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action: UTF8String;
begin
  if DocumentUI <> nil then
  begin
    if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then Exit(DocumentInput(SDLK_ESCAPE, 0));
    if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
    else DocumentUI.Mouse(X, Y);
    FocusDocumentField(DocumentUI.FocusedTarget);
    Action := DocumentUI.TakeAction;
    if Action = uiParticipantsSelect then
    begin
      FocusDocumentField(DocumentUI.ActionTarget);
      DocumentInput(SDLK_RETURN, 0);
    end
    else if Action = uiParticipantsPrevious then DocumentInput(SDLK_LEFT, 0)
    else if Action = uiParticipantsNext then DocumentInput(SDLK_RIGHT, 0)
    else if Action = uiParticipantsContinue then ContinueTournament
    else if Action = uiNavigationBack then DocumentInput(SDLK_ESCAPE, 0);
    Exit(true);
  end;
  Result := inherited ParseMouse(MouseButton, BtnDown, X, Y);
  SetTextInput((Interaction >= 0) and (Interaction <= High(Interactions)) and
    (Interactions[Interaction].Typ = iButton));
end;

constructor TScreenPartyTournamentPlayer.Create;
var
  TournamentPlayerOptions: TUTF8StringArray;
  I: integer;
begin
  inherited Create;

  DocumentField := -1;
  DocumentUI := TDocumentUI.Open(uiScreenTournamentPlayers);
  if DocumentUI <> nil then Exit;

  LoadFromTheme(Theme.PartyTournamentPlayer);

  TournamentPlayerOptions := CreateNumericOptionArray(2, 16);

  Theme.PartyTournamentPlayer.SelectPlayers.oneItemOnly := true;
  Theme.PartyTournamentPlayer.SelectPlayers.showArrows := true;
  SelectPlayers := AddSelectSlide(Theme.PartyTournamentPlayer.SelectPlayers, CountPlayer, TournamentPlayerOptions);

  AddButton(Theme.PartyTournamentPlayer.Player1Name);
  AddButton(Theme.PartyTournamentPlayer.Player2Name);
  AddButton(Theme.PartyTournamentPlayer.Player3Name);
  AddButton(Theme.PartyTournamentPlayer.Player4Name);

  AddButton(Theme.PartyTournamentPlayer.Player5Name);
  AddButton(Theme.PartyTournamentPlayer.Player6Name);
  AddButton(Theme.PartyTournamentPlayer.Player7Name);
  AddButton(Theme.PartyTournamentPlayer.Player8Name);

  AddButton(Theme.PartyTournamentPlayer.Player9Name);
  AddButton(Theme.PartyTournamentPlayer.Player10Name);
  AddButton(Theme.PartyTournamentPlayer.Player11Name);
  AddButton(Theme.PartyTournamentPlayer.Player12Name);

  AddButton(Theme.PartyTournamentPlayer.Player13Name);
  AddButton(Theme.PartyTournamentPlayer.Player14Name);
  AddButton(Theme.PartyTournamentPlayer.Player15Name);
  AddButton(Theme.PartyTournamentPlayer.Player16Name);
  for I := 0 to High(Button) do
  begin
    Button[I].Text[0].Writable := true;
    Button[I].Text[0].NameEntryField := true;
  end;
  SetTextInput(false);

  Interaction := 0;

end;

procedure TScreenPartyTournamentPlayer.OnHide;
begin
  StopTextInput;
  inherited;
end;

procedure TScreenPartyTournamentPlayer.OnShow;
var
  I:    integer;
begin
  if DocumentUI = nil then inherited;

  if not Help.SetHelpID(ID) then
    Log.LogError('No Entry for Help-ID ' + ID + ' (ScreenPartyPlayer)');

  PartyTournament.Clear;

  if not FRestoreNames then
  begin
    if DocumentUI = nil then Interaction := 0;
    // Translate untouched legacy defaults, while retaining actual player names.
    for I := 0 to 15 do
      if (Ini.Name[I] = 'Player' + IntToStr(I + 1)) or
        (Ini.Name[I] = 'Player ' + IntToStr(I + 1)) then
        AssignParticipantName(I, IPlayerTranslated[I])
      else AssignParticipantName(I, Ini.Name[I]);

  end;
  FRestoreNames := false;

  UpdateInterface;
  if DocumentUI <> nil then
  begin
    DocumentField := -1;
    SetTextInput(false);
    SyncDocument;
  end
  else SetTextInput((Interaction >= 0) and (Interaction <= High(Interactions)) and
      (Interactions[Interaction].Typ = iButton));

end;

end.
