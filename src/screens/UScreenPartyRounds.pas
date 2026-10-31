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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/branches/experimental/Lua/src/screens/UScreenPartyOptions.pas $
 * $Id: UScreenPartyOptions.pas 2036 2009-12-14 20:59:44Z whiteshark0 $
 *}

unit UScreenPartyRounds;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UDisplay,
  UDocumentUI,
  UFiles,
  UMenu,
  UMusic,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenPartyRounds = class(TMenu)
    private
      Actual: integer;

      SelectRoundCount: cardinal;
      SelectRound: array [0..6] of cardinal;

      RoundCount: integer;
      Round: array [0..6] of integer;
      RoundMode: array [0..98] of integer;

      IModeNames: array of UTF8String;
      IModeIDs: array of integer;
      DocumentUI: TDocumentUI;
      DocumentRound: integer;
      DocumentDirty: boolean;
      DocumentNeedsReveal: boolean;
      DocumentRevealRound: integer;

      procedure SyncDocument;
      procedure ReadDocumentSelection;
      procedure MoveDocumentSelection(Direction: integer);
      procedure ChangeDocumentValue(Delta: integer);
      procedure ChooseDocumentValue(const Target: UTF8String);
      procedure UpdateInterface;
      procedure StartParty;
    public
      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      procedure OnWindowResized; override;
      procedure InteractNext; override;
      procedure InteractPrev; override;
  end;

const
  ID='ID_032';   //for help system
  uiPartyRoundsRole = 'party-rounds';
  uiPartyRoundsData = 'partyRounds';
  uiPartyRoundsPrevious = 'party.rounds.previous';
  uiPartyRoundsNext = 'party.rounds.next';
  uiPartyRoundsChoose = 'party.rounds.choose';
  uiPartyRoundsSelect = 'party.rounds.select';
  uiPartyRoundsStart = 'party.rounds.start';

implementation

uses
  UGraphic,
  UHelp,
  UIni,
  ULanguage,
  ULog,
  UMain,
  UMenuSelectSlide,
  UParty,
  UPlaylist,
  USong,
  USongs,
  UUnicodeUtils,
  Math;

destructor TScreenPartyRounds.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenPartyRounds.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenPartyRounds.DrawFG: boolean;
begin
  if DocumentUI <> nil then
  begin
    SyncDocument;
    Exit(DocumentUI.Draw(false, true));
  end;
  Result := inherited;
end;

procedure TScreenPartyRounds.OnWindowResized;
begin
  inherited;
  if DocumentUI <> nil then DocumentNeedsReveal := true;
end;

procedure TScreenPartyRounds.ReadDocumentSelection;
var Target: UTF8String; Index: integer;
begin
  Target := DocumentUI.FocusedTarget;
  if Target = 'count' then Index := -1
  else if not TryStrToInt(Target, Index) then Exit;
  if (Index < -1) or (Index >= RoundCount + 2) then Exit;
  if DocumentRound <> Index then
  begin
    DocumentDirty := true;
    DocumentNeedsReveal := true;
  end;
  DocumentRound := Index;
  if Index >= 0 then DocumentRevealRound := Index;
end;

procedure TScreenPartyRounds.MoveDocumentSelection(Direction: integer);
var I, Index: integer; Target: UTF8String;
begin
  // Skip optional theme commands while walking the round fields in document order.
  for I := 0 to RoundCount + 3 do
  begin
    DocumentUI.Key(Direction);
    Target := DocumentUI.FocusedTarget;
    if (Target = 'count') or (TryStrToInt(Target, Index) and
       (Index >= 0) and (Index < RoundCount + 2)) then
    begin
      ReadDocumentSelection;
      Exit;
    end;
  end;
end;

procedure TScreenPartyRounds.ChangeDocumentValue(Delta: integer);
begin
  DocumentDirty := true;
  if DocumentRound = -1 then
    RoundCount := EnsureRange(RoundCount + Delta, 0, High(RoundMode) - 1)
  else if (DocumentRound >= 0) and (DocumentRound < RoundCount + 2) and (Length(IModeIDs) > 0) then
    RoundMode[DocumentRound] := EnsureRange(RoundMode[DocumentRound] + Delta, 0, High(IModeIDs));
end;

procedure TScreenPartyRounds.ChooseDocumentValue(const Target: UTF8String);
var Separator, Index, Choice: integer;
begin
  Separator := Pos(':', Target);
  if (Separator <= 0) or not TryStrToInt(Copy(Target, Separator + 1, MaxInt), Choice) then Exit;
  if Copy(Target, 1, Separator - 1) = 'count' then
  begin
    if (Choice < 2) or (Choice > Length(RoundMode)) then Exit;
    RoundCount := Choice - 2;
    DocumentRound := -1;
    DocumentDirty := true;
    Exit;
  end;
  if not TryStrToInt(Copy(Target, 1, Separator - 1), Index) then Exit;
  if (Index < 0) or (Index >= RoundCount + 2) or
    (Choice < 0) or (Choice >= Length(IModeIDs)) then Exit;
  DocumentRound := Index;
  DocumentRevealRound := Index;
  DocumentNeedsReveal := true;
  RoundMode[Index] := Choice;
  DocumentDirty := true;
end;

procedure TScreenPartyRounds.SyncDocument;
var I, Selection: integer; Prefix: UTF8String;
begin
  if DocumentDirty then
  begin
    DocumentUI.SetModel(uiPartyRoundsData + '.count', IntToStr(RoundCount + 2), 1);
    DocumentUI.SetModel(uiPartyRoundsData + '.focus', IntToStr(DocumentRound), 1);
    DocumentUI.SetModel(uiPartyRoundsData + '.previousCount', IntToStr(Ord(RoundCount > 0)), 2);
    DocumentUI.SetModel(uiPartyRoundsData + '.nextCount', IntToStr(Ord(RoundCount < High(RoundMode) - 1)), 2);
    DocumentUI.SetModel(uiPartyRoundsData + '.minimumCount', '2', 1);
    DocumentUI.SetModel(uiPartyRoundsData + '.maximumCount', IntToStr(Length(RoundMode)), 1);
    DocumentUI.SetArray(uiPartyRoundsData + '.counts', Length(RoundMode) - 1);
    for I := 2 to Length(RoundMode) do
      DocumentUI.SetModel(uiPartyRoundsData + '.counts[' + IntToStr(I - 2) + '].value', IntToStr(I), 1);
    DocumentUI.SetArray(uiPartyRoundsData + '.modes', Length(IModeNames));
    for I := 0 to High(IModeNames) do
    begin
      Prefix := uiPartyRoundsData + '.modes[' + IntToStr(I) + '].';
      DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
      DocumentUI.SetModel(Prefix + 'name', IModeNames[I]);
    end;
    DocumentUI.SetArray(uiPartyRoundsData + '.rounds', RoundCount + 2);
    for I := 0 to RoundCount + 1 do
    begin
      Prefix := uiPartyRoundsData + '.rounds[' + IntToStr(I) + '].';
      Selection := EnsureRange(RoundMode[I], 0, Max(0, High(IModeNames)));
      DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
      DocumentUI.SetModel(Prefix + 'label', Format(Language.Translate('PARTY_SELECTMODE'), [I + 1]));
      if Length(IModeNames) > 0 then DocumentUI.SetModel(Prefix + 'name', IModeNames[Selection])
      else DocumentUI.SetModel(Prefix + 'name', '');
      DocumentUI.SetModel(Prefix + 'mode', IntToStr(Selection), 1);
      DocumentUI.SetModel(Prefix + 'previous', IntToStr(Ord(Selection > 0)), 2);
      DocumentUI.SetModel(Prefix + 'next', IntToStr(Ord(Selection < High(IModeIDs))), 2);
    end;
    DocumentDirty := false;
  end;
  if DocumentRound = -1 then DocumentUI.Focus('round-count')
  else DocumentUI.Focus('round-mode-' + IntToStr(DocumentRound));
  if DocumentNeedsReveal then
  begin
    DocumentRevealRound := EnsureRange(DocumentRevealRound, 0, RoundCount + 1);
    DocumentUI.Reveal('round-row-' + IntToStr(DocumentRevealRound));
    DocumentNeedsReveal := false;
  end;
end;

function TScreenPartyRounds.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action, Target: UTF8String; Selection: integer;
begin
  if DocumentUI = nil then Exit(inherited);
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then
    Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
  else DocumentUI.Mouse(X, Y);
  if BtnDown then
  begin
    if MouseButton = SDL_BUTTON_WHEELUP then DocumentUI.Scroll(-1)
    else if MouseButton = SDL_BUTTON_WHEELDOWN then DocumentUI.Scroll(1);
  end;
  ReadDocumentSelection;
  Action := DocumentUI.TakeAction;
  if (Action = uiPartyRoundsPrevious) or (Action = uiPartyRoundsNext) or (Action = uiPartyRoundsSelect) then
  begin
    Target := DocumentUI.ActionTarget;
    if Target = 'count' then Selection := -1
    else if not TryStrToInt(Target, Selection) then Selection := -2;
    if (Selection >= -1) and (Selection < RoundCount + 2) then
    begin
      DocumentNeedsReveal := DocumentRound <> Selection;
      DocumentRound := Selection;
      if Selection >= 0 then DocumentRevealRound := Selection;
      DocumentDirty := true;
    end
    else Exit(true);
  end;
  if Action = uiPartyRoundsPrevious then
    ParseInput(SDLK_LEFT, 0, true)
  else if Action = uiPartyRoundsNext then
    ParseInput(SDLK_RIGHT, 0, true)
  else if Action = uiPartyRoundsChoose then
    ChooseDocumentValue(DocumentUI.ActionTarget)
  else if Action = uiPartyRoundsStart then
    StartParty
  else if Action = uiNavigationBack then
    Exit(ParseInput(SDLK_ESCAPE, 0, true));
  Result := true;
end;

procedure TScreenPartyRounds.InteractNext;
var
  I: integer;
begin
  if DocumentUI <> nil then
  begin
    MoveDocumentSelection(uiKeyNext);
    Exit;
  end;

  if (Interaction = high(Theme.PartyRounds.SelectRound) + 1) and (Actual + high(Theme.PartyRounds.SelectRound) <= RoundCount) then
  begin
    Actual := Actual + 1;

    // update slides
    for I := 0 to high(Theme.PartyRounds.SelectRound) do
    begin
      SelectsS[SelectRound[I]].Text.Text := Format(Language.Translate('PARTY_SELECTMODE'), [(Actual + I + 1)]);
      SelectsS[SelectRound[I]].SetSelectOpt(RoundMode[Actual + I]);
    end;

  end
  else
    inherited InteractNext;

end;

procedure TScreenPartyRounds.InteractPrev;
var
  I: integer;
begin
  if DocumentUI <> nil then
  begin
    MoveDocumentSelection(uiKeyPrevious);
    Exit;
  end;

  if (Interaction = 1) and (Actual > 0) then
  begin
    Actual := Actual - 1;

    // update slides
    for I := 0 to high(Theme.PartyRounds.SelectRound) do
    begin
      SelectsS[SelectRound[I]].Text.Text := Format(Language.Translate('PARTY_SELECTMODE'), [(Actual + I + 1)]);
      SelectsS[SelectRound[I]].SetSelectOpt(RoundMode[Actual + I]);
    end;

  end
  else
    inherited InteractPrev;

end;

procedure TScreenPartyRounds.UpdateInterface;
  var
    I: integer;
    ActualRounds: integer;
begin
  ActualRounds := RoundCount + 2;
  if DocumentUI <> nil then
  begin
    if DocumentRound >= ActualRounds then DocumentRound := -1;
    Exit;
  end;

  for I := 0 to High(SelectRound) do
    SelectsS[SelectRound[I]].Visible := (I < ActualRounds);
end;

procedure TScreenPartyRounds.StartParty;
  var
    GameRounds: ARounds;
    I: integer;
begin
  if Length(IModeIDs) = 0 then Exit;
  SetLength(GameRounds, RoundCount + 2);

  for I := 0 to High(GameRounds) do
    GameRounds[I] := IModeIds[RoundMode[I]];

  // start party game
  if (Party.StartGame(GameRounds)) then
  begin
    FadeTo(@ScreenPartyNewRound, SoundLib.Start);
  end
  else
  begin
    //error starting party game
    ScreenPopupError.ShowPopup(Language.Translate('ERROR_CAN_NOT_START_PARTY'));
  end;
end;

function TScreenPartyRounds.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
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

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE:
        begin
          AudioPlayback.PlaySound(SoundLib.Back);
          FadeTo(@ScreenPartyPlayer);
        end;

      SDLK_TAB:
      begin
        ScreenPopupHelp.ShowPopup();
      end;

      SDLK_RETURN: StartParty;

      // Up and Down could be done at the same time,
      // but I don't want to declare variables inside
      // functions like this one, called so many times
      SDLK_DOWN:    InteractNext;
      SDLK_UP:      InteractPrev;
      SDLK_RIGHT:
        begin
          AudioPlayback.PlaySound(SoundLib.Option);
          if DocumentUI <> nil then
          begin
            ChangeDocumentValue(1);
            Exit;
          end;
          InteractInc;

          if Interaction = 0 then
            UpdateInterface
          else
            RoundMode[Actual + Interaction - 1] := Round[Interaction - 1];
        end;
      SDLK_LEFT:
        begin
          AudioPlayback.PlaySound(SoundLib.Option);
          if DocumentUI <> nil then
          begin
            ChangeDocumentValue(-1);
            Exit;
          end;
          InteractDec;

          if Interaction = 0 then
            UpdateInterface
          else
            RoundMode[Actual + Interaction - 1] := Round[Interaction - 1];
        end;
    end;
  end;
end;

constructor TScreenPartyRounds.Create;
var
  I: integer;
  IRoundCount:  array[0..97] of UTF8String;
begin
  inherited Create;
  RoundCount := 5;
  DocumentRound := -1;
  DocumentDirty := true;
  DocumentNeedsReveal := true;
  for I := 0 to High(RoundMode) do RoundMode[I] := 0;
  SetLength(IModeNames, 1);
  IModeNames[0] := '---';
  DocumentUI := TDocumentUI.Open(uiPartyRoundsRole);
  if DocumentUI <> nil then Exit;

  for I := 0 to 97 do
    IRoundCount[I] := IntToStr(I + 2);

  //Load Screen From Theme
  LoadFromTheme(Theme.PartyRounds);

  Theme.PartyRounds.SelectRoundCount.oneItemOnly := true;
  Theme.PartyRounds.SelectRoundCount.showArrows := true;
  SelectRoundCount := AddSelectSlide(Theme.PartyRounds.SelectRoundCount, RoundCount, IRoundCount);

  SetLength(IModeNames, 1);
  IModeNames[0] := '---';
  for I := 0 to high(Theme.PartyRounds.SelectRound) do
  begin
    Theme.PartyRounds.SelectRound[I].oneItemOnly := true;
    Theme.PartyRounds.SelectRound[I].showArrows := true;
    SelectRound[I] := AddSelectSlide(Theme.PartyRounds.SelectRound[I], Round[I], IModeNames);
    SelectsS[SelectRound[I]].Text.Text := Format(Language.Translate('PARTY_SELECTMODE'), [(I + 1)]);
  end;

  for I := 0 to High(RoundMode) do
    RoundMode[I] := 0;

  Interaction := 0;
  Actual := 0;
end;

procedure TScreenPartyRounds.OnShow;
  var
    ModeList: AParty_ModeList;
    temp: TParty_RoundList;
    I, J: integer;
begin
  if DocumentUI = nil then inherited;

  if not Help.SetHelpID(ID) then
    Log.LogError('No Entry for Help-ID ' + ID + ' (ScreenPartyRounds)');

  // check if there are loaded modes
  if Party.ModesAvailable then
  begin
    UpdateInterface;

    ModeList := Party.GetAvailableModes;
    SetLength(IModeNames, Length(ModeList));
    SetLength(IModeIds, Length(ModeList));

    // sort
    for I := Length(ModeList) - 1 downto 1 do
    begin
      for J := 2 to i do
      begin
        If UTF8CompareText(ModeList[J - 1].Name, ModeList[J].Name) > 0 then
        begin
          temp := ModeList[J - 1];
          ModeList[J - 1] := ModeList[J];
          ModeList[J] := temp;
        end;
      end;
    end;

    for I := 0 to High(ModeList) do
    begin
      IModeNames[I] := ModeList[I].Name;
      IModeIds[I]   := ModeList[I].Index;
    end;

    for I := 0 to High(RoundMode) do
      RoundMode[I] := EnsureRange(RoundMode[I], 0, High(IModeIDs));
    if DocumentUI <> nil then
    begin
      DocumentDirty := true;
      DocumentNeedsReveal := true;
      SyncDocument;
    end
    else
      for I := 0 to High(SelectRound) do
        UpdateSelectSlideOptions(SelectRound[I], IModeNames, Round[I]);
  end
  else
  begin
    // no mode available for current player setup
    ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_MODES_FOR_CURRENT_SETUP'));
    Party.Clear;
    Display.AbortScreenChange;
  end;
end;

end.
