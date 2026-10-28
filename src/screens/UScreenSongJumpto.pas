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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenSongJumpto.pas $
 * $Id: UScreenSongJumpto.pas 2199 2010-03-14 20:56:20Z brunzelchen $
 *}

unit UScreenSongJumpto;

{$mode delphi}
{$I switches.inc}

interface

uses UMenu, USongs, USong, UThemes, sdl2, SysUtils, Classes, UMenuButton;

const
  FILTER_SLOTS = 3;
  SEARCH_DEBOUNCE_MS = 200;

type
  TFilterSuggestionMenu = class(TMenu)
  public
    function Row(Index: integer): TButton;
    function RowCount: integer;
  end;

  TScreenSongJumpto = class(TMenu)
  private
    fVisible, fPlaylistSearch, fLockShortcutPending: boolean;
    fFooter, fLockIcons: TMenu;
    fSuggestions: TFilterSuggestionMenu;
    fValues: TStringList;
    fMatches: array of integer;
    fSuggestionContext, fSuggestionQuery: UTF8String;
    fSuggestionFocus, fPending: boolean;
    fChangedTick: cardinal;
    fSuggestionIndex, fSuggestionFirst, fSuggestionRows: integer;
    fSuggestionX, fSuggestionY, fSuggestionW: single;
    fLastPlayed, fVisSongs, fFocus, fFirst, fPlaylist: integer;
    fRows: TSongFilterRows;
    fSlotKinds: array[0..FILTER_SLOTS-1] of integer;
    fInputs, fCategories: array[0..FILTER_SLOTS-1] of integer;
    fActions: array[0..3] of integer;
    procedure UpdateSuggestions;
    procedure DrawSuggestions;
    procedure AcceptSuggestion;
    procedure FlushChanges;
    function SuggestionPrefix: UTF8String;
    procedure SetVisible(Value: boolean);
    procedure SetTextFound(Count: cardinal; SelectedSong: TSong);
    function ApplyFilter: cardinal;
    function FilterSummary: UTF8String;
    procedure RefreshRows;
    procedure Changed;
    procedure AddRow;
    procedure RemoveRow(Index: integer);
    procedure ActivateAction(Action: integer);
    procedure MoveFocus(Direction: integer);
  public
    constructor Create; override;
    destructor Destroy; override;
    function ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    procedure OnShow; override;
    procedure ResetFilters;
    function Draw: boolean; override;
    property Visible: boolean read fVisible write SetVisible;
  end;

implementation

uses Math, UCommon, UDisplay, UFiles, UMusic, UGraphic, ULibraryLockdown, ULockdownUI,
  UHelp, UIni, ULanguage, ULog, UMain, UParty, URenderer, UPlaylist,
  UScreenSong, UUnicodeUtils, UPath, UMenuInteract, UMenuText, UAge, UFilterTerms;

const ID = 'ID_016';

function TFilterSuggestionMenu.Row(Index: integer): TButton;
begin
  Result := Button[Index];
end;

function TFilterSuggestionMenu.RowCount: integer;
begin
  Result := Length(Button);
end;

constructor TScreenSongJumpto.Create;
var S, I: integer; Category: TThemeSelectSlide; Input: TThemeButton;
begin
  inherited Create;
  AddText(Theme.SongJumpto.TextFound);
  LoadFromTheme(Theme.SongJumpto);
  for S := 0 to FILTER_SLOTS - 1 do
  begin
    Category := Theme.SongJumpto.SelectSlideType;
    Inc(Category.Y, S * Theme.SongJumpto.RowSpacing);
    fCategories[S] := AddSelectSlide(Category, fSlotKinds[S], Theme.SongJumpto.IType);
    Input := Theme.SongJumpto.ButtonSearchText;
    Inc(Input.Y, S * Theme.SongJumpto.RowSpacing);
    fInputs[S] := AddButton(Input);
    Button[fInputs[S]].Text[0].Writable := true;
  end;
  for I := 0 to 3 do
    fActions[I] := AddButton(Theme.SongJumpto.FilterActions[I]);
  fValues := TStringList.Create;
  fValues.Sorted := true;
  fValues.CaseSensitive := true;
  fSuggestions := TFilterSuggestionMenu.Create;
  if Length(Theme.SongJumpto.Statics) > 0 then
    fSuggestions.AddStatic(Theme.SongJumpto.SuggestionPanel);
  fFooter := TMenu.Create;
  fFooter.LoadFromTheme(Theme.SongJumpto.Footer);
  if Theme.SongJumpto.CustomLockIcons then
  begin
    fLockIcons := TMenu.Create;
    fLockIcons.AddStatic(Theme.SongJumpto.LockedIcon);
    fLockIcons.AddStatic(Theme.SongJumpto.UnlockedIcon);
  end;
  SetLength(fRows, 1);
  fPlaylist := -1;
end;

destructor TScreenSongJumpto.Destroy;
begin
  fValues.Free;
  fSuggestions.Free;
  fLockIcons.Free;
  fFooter.Free;
  inherited;
end;

function TScreenSongJumpto.FilterSummary: UTF8String;
var R: integer;
begin
  Result := '';
  for R := 0 to High(fRows) do
    if Trim(fRows[R].Query) <> '' then
    begin
      if Result <> '' then Result := Result + ' / ';
      Result := Result + Theme.SongJumpto.IType[Ord(fRows[R].Kind)] + ': ' + fRows[R].Query;
    end;
end;

procedure TScreenSongJumpto.RefreshRows;
var S, R, I, Delta: integer; OffsetY: real;
begin
  for I := 0 to High(Statics) do Statics[I].Texture.Y := Theme.SongJumpto.Statics[I].Y;
  for I := 0 to High(Theme.SongJumpto.Text) do Text[I + 1].Y := Theme.SongJumpto.Text[I].Y;
  Text[0].Y := Theme.SongJumpto.TextFound.Y;
  for I := 0 to 3 do Button[fActions[I]].Y := Theme.SongJumpto.FilterActions[I].Y;
  for S := 0 to FILTER_SLOTS - 1 do
  begin
    SelectsS[fCategories[S]].Y := Theme.SongJumpto.SelectSlideType.Y + S * Theme.SongJumpto.RowSpacing;
    Button[fInputs[S]].Y := Theme.SongJumpto.ButtonSearchText.Y + S * Theme.SongJumpto.RowSpacing;
  end;
  if fFocus < Length(fRows) then
  begin
    if fFocus < fFirst then fFirst := fFocus;
    if fFocus >= fFirst + FILTER_SLOTS then fFirst := fFocus - FILTER_SLOTS + 1;
  end;
  fFirst := EnsureRange(fFirst, 0, Max(0, Length(fRows) - FILTER_SLOTS));
  for S := 0 to FILTER_SLOTS - 1 do
  begin
    R := fFirst + S;
    Button[fInputs[S]].Visible := R < Length(fRows);
    SelectsS[fCategories[S]].Visible := R < Length(fRows);
    if R >= Length(fRows) then Continue;
    fSlotKinds[S] := Ord(fRows[R].Kind);
    UpdateSelectSlideOptions(fCategories[S], Theme.SongJumpto.IType, fSlotKinds[S]);
    Button[fInputs[S]].Text[0].Text := fRows[R].Query;
    Button[fInputs[S]].Selected := (fFocus = R);
    SelectsS[fCategories[S]].Selected := (fFocus = R);
  end;
  Button[fActions[0]].Visible := false;
  Button[fActions[1]].Text[0].Text := 'x';
  Button[fActions[2]].Visible := false;
  Button[fActions[3]].Text[0].Text := '';
  for I := 0 to 3 do Button[fActions[I]].Selected := fFocus = Length(fRows) + I;
  if Theme.SongJumpto.AutoHeightStatic > 0 then
  begin
    Delta := (FILTER_SLOTS - Min(FILTER_SLOTS, Length(fRows))) * Theme.SongJumpto.RowSpacing;
    Text[0].Y := Theme.SongJumpto.TextFound.Y - Delta;
    for I := 0 to 3 do
      if I = 0 then Button[fActions[I]].Y := Theme.SongJumpto.FilterActions[I].Y - Delta;
    I := Theme.SongJumpto.AutoHeightStatic - 1;
    if (I <= High(Statics)) and (I <= High(Theme.SongJumpto.Statics)) then
      Statics[I].Texture.H := Theme.SongJumpto.Statics[I].H - Delta;
  end;
  if Length(fFooter.Text) >= 6 then
    if LibraryLockdown.Active then fFooter.Text[5].Text := Language.Translate('FILTER_UNLOCK')
    else fFooter.Text[5].Text := Language.Translate('FILTER_LOCK');
  if Theme.SongJumpto.CenterVertical and (Length(Statics) > 0) then
  begin
    OffsetY := (RenderH - Statics[0].Texture.H) / 2 - Statics[0].Texture.Y;
    for I := 0 to High(Statics) do Statics[I].Texture.Y := Statics[I].Texture.Y + OffsetY;
    for I := 0 to High(Text) do Text[I].Y := Text[I].Y + OffsetY;
    for I := 0 to High(Button) do Button[I].Y := Button[I].Y + OffsetY;
    for I := 0 to High(SelectsS) do SelectsS[I].Y := SelectsS[I].Y + OffsetY;
  end;
end;

procedure TScreenSongJumpto.Changed;
begin
  fPending := true;
  fChangedTick := SDL_GetTicks;
  fSuggestionFocus := false;
  RefreshRows;
end;

procedure TScreenSongJumpto.FlushChanges;
var SelectedSong: TSong;
begin
  if not fPending then Exit;
  fPending := false;
  SelectedSong := nil;
  if (ScreenSong.Interaction >= 0) and (ScreenSong.Interaction < Length(CatSongs.Song)) then
    SelectedSong := CatSongs.Song[ScreenSong.Interaction];
  SetTextFound(ApplyFilter, SelectedSong);
  ScreenSong.NextRandomSearchIdx := CatSongs.VisibleSongs;
end;

procedure TScreenSongJumpto.AddRow;
begin
  // Reuse an empty trailing row rather than adding a series of empty rows.
  if Trim(fRows[High(fRows)].Query) <> '' then SetLength(fRows, Length(fRows) + 1);
  fFocus := High(fRows);
  RefreshRows;
end;

procedure TScreenSongJumpto.RemoveRow(Index: integer);
var R: integer;
begin
  if Length(fRows) = 1 then fRows[0].Query := ''
  else
  begin
    for R := Index to High(fRows) - 1 do fRows[R] := fRows[R + 1];
    SetLength(fRows, Length(fRows) - 1);
  end;
  fFocus := Min(Index, High(fRows));
  Changed;
end;

procedure TScreenSongJumpto.ActivateAction(Action: integer);
begin
  case Action of
    0: AddRow;
    1: begin SetLength(fRows, 1); fRows[0].Query := ''; fRows[0].Kind := fltAll;
         fFocus := 0; fFirst := 0; Changed; end;
    2: Visible := false;
    3: begin FlushChanges; ToggleLibraryLockdown; fSuggestionContext := #1; end;
  end;
end;

procedure TScreenSongJumpto.MoveFocus(Direction: integer);
begin
  fFocus := (fFocus + Direction + Length(fRows) + 4) mod (Length(fRows) + 4);
  if (fFocus = Length(fRows)) or (fFocus = Length(fRows) + 2) then Inc(fFocus, Direction);
  if (fFocus = Length(fRows)) or (fFocus = Length(fRows) + 2) then Inc(fFocus, Direction);
  RefreshRows;
end;

function TScreenSongJumpto.ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean = false): boolean;
var S: integer;
begin
  Result := true;
  if not PressedDown then Exit;
  if (PressedKey = SDLK_SPACE) and (SDL_GetModState and KMOD_CTRL <> 0) then
  begin
    FlushChanges;
    UpdateSuggestions;
    fSuggestionFocus := Length(fMatches) > 0;
    Exit;
  end;
  if fSuggestionFocus then
    case PressedKey of
      SDLK_UP: begin fSuggestionIndex := Max(0, fSuggestionIndex - 1); Exit; end;
      SDLK_DOWN: begin fSuggestionIndex := Min(High(fMatches), fSuggestionIndex + 1); Exit; end;
      SDLK_RETURN: begin AcceptSuggestion; Exit; end;
      SDLK_ESCAPE: begin
    fSuggestionFocus := false;
    fSuggestionContext := #1;
    SetLength(fMatches, 0);
    Exit;
  end;
    end;
  if SDL_GetModState and KMOD_ALT <> 0 then
  begin
    case PressedKey of
      SDLK_c: begin ActivateAction(1); Exit; end;
      SDLK_l: begin fLockShortcutPending := true; Exit; end;
    end;
    Exit;
  end;
  if (fFocus < Length(fRows)) and (IsAlphaNumericChar(CharCode) or
    IsPunctuationChar(CharCode) or (CharCode = 32)) then
  begin
    fRows[fFocus].Query := fRows[fFocus].Query + UCS4ToUTF8String(CharCode);
    Changed;
    Exit;
  end;
  case PressedKey of
    SDLK_F1: ScreenPopupHelp.ShowPopup;
    SDLK_TAB:
      if SDL_GetModState and KMOD_SHIFT <> 0 then MoveFocus(-1) else MoveFocus(1);
    SDLK_ESCAPE: begin Visible := false; AudioPlayback.PlaySound(SoundLib.Back); end;
    SDLK_RETURN: if fFocus < Length(fRows) then Visible := false
                 else ActivateAction(fFocus - Length(fRows));
    SDLK_SPACE: if fFocus >= Length(fRows) then ActivateAction(fFocus - Length(fRows));
    SDLK_BACKSPACE:
      if fFocus < Length(fRows) then
      begin
        if fRows[fFocus].Query = '' then RemoveRow(fFocus)
        else
        begin
          S := fFocus - fFirst;
          Button[fInputs[S]].Text[0].DeleteLastLetter;
          fRows[fFocus].Query := Button[fInputs[S]].Text[0].Text;
          Changed;
        end;
      end;
    SDLK_DOWN:
      if not Repeated then
      begin
        if (fFocus = High(fRows)) and (Trim(fRows[fFocus].Query) <> '') then AddRow
        else MoveFocus(1);
      end;
    SDLK_UP: MoveFocus(-1);
    SDLK_INSERT: AddRow;
    SDLK_LEFT, SDLK_RIGHT:
      if fFocus < Length(fRows) then
      begin
        S := Ord(fRows[fFocus].Kind);
        if PressedKey = SDLK_LEFT then S := (S + Ord(High(TSongFilter))) mod (Ord(High(TSongFilter)) + 1)
        else S := (S + 1) mod (Ord(High(TSongFilter)) + 1);
        fRows[fFocus].Kind := TSongFilter(S);
        Changed;
      end
      else if PressedKey = SDLK_LEFT then MoveFocus(-1) else MoveFocus(1);
  end;
end;

function TScreenSongJumpto.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var S, R, I: integer; LX, LY: real; Area: TMouseOverRect;
  function Inside(B: integer): boolean;
  begin
    Result := Button[B].Visible and (LX >= Button[B].X) and (LX <= Button[B].X + Button[B].W) and
      (LY >= Button[B].Y) and (LY <= Button[B].Y + Button[B].H);
  end;
begin
  Result := true;
  if not BtnDown then Exit;
  if (Length(fMatches) > 0) and (X >= fSuggestionX) and
    (X <= fSuggestionX + fSuggestionW) and (Y >= fSuggestionY) and
    (Y < fSuggestionY + fSuggestionRows * Theme.SongJumpto.SuggestionRowHeight) then
  begin
    if (MouseButton = SDL_BUTTON_WHEELUP) or (MouseButton = SDL_BUTTON_WHEELDOWN) then fSuggestionFocus := false;
    if MouseButton = SDL_BUTTON_WHEELUP then fSuggestionFirst := Max(0, fSuggestionFirst - 1)
    else if MouseButton = SDL_BUTTON_WHEELDOWN then
      fSuggestionFirst := Min(Max(0, Length(fMatches) - fSuggestionRows), fSuggestionFirst + 1)
    else if MouseButton = SDL_BUTTON_LEFT then
    begin
      fSuggestionIndex := fSuggestionFirst + Trunc((Y - fSuggestionY) / Theme.SongJumpto.SuggestionRowHeight);
      AcceptSuggestion;
    end;
    Exit;
  end;
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) then begin Visible := false; Exit; end;
  if (MouseButton = SDL_BUTTON_WHEELUP) or (MouseButton = SDL_BUTTON_WHEELDOWN) then
  begin
    if MouseButton = SDL_BUTTON_WHEELUP then fFirst := Max(0, fFirst - 1)
    else fFirst := Min(Max(0, Length(fRows) - FILTER_SLOTS), fFirst + 1);
    fFocus := EnsureRange(fFocus, fFirst, Min(High(fRows), fFirst + FILTER_SLOTS - 1));
    RefreshRows; Exit;
  end;
  if MouseButton <> SDL_BUTTON_LEFT then Exit;
  // UScreenSong already converts mouse input to theme coordinates.
  LX := X;
  LY := Y;
  for S := 0 to FILTER_SLOTS - 1 do
  begin
    R := fFirst + S;
    if R >= Length(fRows) then Break;
    if Inside(fInputs[S]) then begin fFocus := R; RefreshRows; Exit; end;
    Area := SelectsS[fCategories[S]].GetMouseOverArea;
    if (LX >= Area.X) and (LX <= Area.X + Area.W) and
       (LY >= Area.Y) and (LY < Area.Y + Area.H) then
      begin
        fFocus := R;
        if LX < Area.X + Area.W / 2 then ParseInput(SDLK_LEFT, 0, true)
        else ParseInput(SDLK_RIGHT, 0, true);
        Exit;
      end;
  end;
  for I := 0 to 3 do
    if Inside(fActions[I]) then begin fFocus := Length(fRows) + I; ActivateAction(I); Exit; end;
end;

function TScreenSongJumpto.ApplyFilter: cardinal;
var I: integer; Active: boolean;
begin
  Active := false;
  for I := 0 to High(fRows) do Active := Active or (Trim(fRows[I].Query) <> '');
  if fPlaylistSearch and (PlaylistMan.CurPlayList = fPlaylist) then
  begin
    PlaylistMan.SetPlayList(fPlaylist, fLastPlayed);
    if not Active then Exit(CatSongs.VisibleSongs);
  end;
  Result := CatSongs.SetFilters(fRows);
  if fPlaylistSearch and (PlaylistMan.CurPlayList = fPlaylist) then
  begin
    Result := 0;
    for I := 0 to High(CatSongs.Song) do
    begin
      if CatSongs.Song[I].Visible and (PlaylistMan.GetIndexbySongID(I) = -1) then
        CatSongs.Song[I].Visible := false;
      if CatSongs.Song[I].Visible then Inc(Result);
    end;
    CatSongs.ResetVisibleIndexCache;
  end;
end;

procedure TScreenSongJumpto.SetVisible(Value: boolean);
begin
  if not Value then FlushChanges;
  if not fVisible and Value then OnShow;
  SetTextInput(Value);
  fVisible := Value;
end;

procedure TScreenSongJumpto.ResetFilters;
begin
  // Search rows are temporary. Lockdown freezes the library, not these queries.
  SetLength(fRows, 1);
  fRows[0].Query := '';
  fRows[0].Kind := fltAll;
  fPlaylistSearch := false;
  fPlaylist := -1;
  fFocus := 0; fFirst := 0;
end;

procedure TScreenSongJumpto.OnShow;
var Country: UTF8String;
begin
  inherited;
  fSuggestionContext := #1;
  fSuggestionFocus := false;
  SetLength(fMatches, 0);
  Help.SetHelpID(ID);
  Country := Ini.AgeCountry;
  if Country = '' then Country := Language.Translate('OPTION_VALUE_AGE_DEFAULT');
  Theme.SongJumpto.IType[9] := Language.Translate('SONG_JUMPTO_TYPE10') + ' (' + Country + ')';
  if CatSongs.CatNumShow <> -2 then
  begin
    ResetFilters;
    fPlaylistSearch := (CatSongs.CatNumShow = -3) and (PlaylistMan.CurPlayList <> -1);
    fPlaylist := PlaylistMan.CurPlayList;
    Text[0].Text := Format(Theme.SongJumpto.SongsFound, [CatSongs.VisibleSongs]);
  end;
  fFocus := 0; fFirst := 0;
  fLastPlayed := ScreenSong.Interaction;
  RefreshRows;
end;

function TScreenSongJumpto.Draw: boolean;
var I: integer; X, Y, W, H, Z: real;
  procedure Outline(B: integer);
  begin
    if not Button[B].Visible or not Button[B].Selected or
      (Theme.SongJumpto.FocusWidth <= 0) or (Theme.SongJumpto.FocusAlpha <= 0) then Exit;
    X := Button[B].X; Y := Button[B].Y; W := Button[B].W; H := Button[B].H;
    Z := Button[B].Z + 0.003;
    Renderer.DrawLine(X, Y, X+W, Y, Z, Theme.SongJumpto.FocusWidth, Theme.SongJumpto.FocusColor.R,
      Theme.SongJumpto.FocusColor.G, Theme.SongJumpto.FocusColor.B, Theme.SongJumpto.FocusAlpha);
    Renderer.DrawLine(X+W, Y, X+W, Y+H, Z, Theme.SongJumpto.FocusWidth, Theme.SongJumpto.FocusColor.R,
      Theme.SongJumpto.FocusColor.G, Theme.SongJumpto.FocusColor.B, Theme.SongJumpto.FocusAlpha);
    Renderer.DrawLine(X+W, Y+H, X, Y+H, Z, Theme.SongJumpto.FocusWidth, Theme.SongJumpto.FocusColor.R,
      Theme.SongJumpto.FocusColor.G, Theme.SongJumpto.FocusColor.B, Theme.SongJumpto.FocusAlpha);
    Renderer.DrawLine(X, Y+H, X, Y, Z, Theme.SongJumpto.FocusWidth, Theme.SongJumpto.FocusColor.R,
      Theme.SongJumpto.FocusColor.G, Theme.SongJumpto.FocusColor.B, Theme.SongJumpto.FocusAlpha);
  end;
begin
  if fPending and (SDL_GetTicks - fChangedTick >= SEARCH_DEBOUNCE_MS) then FlushChanges;
  if not fPending then UpdateSuggestions;
  if fLockShortcutPending and (SDL_GetModState and KMOD_ALT = 0) then
  begin
    fLockShortcutPending := false;
    FlushChanges;
    ToggleLibraryLockdown;
    fSuggestionContext := #1;
  end;
  Renderer.ClearFrameBuffer(CLEAR_DEPTH);
  Result := inherited Draw;
  for I := 0 to FILTER_SLOTS - 1 do
  begin
    Outline(fInputs[I]);
  end;
  for I := 0 to 3 do Outline(fActions[I]);
  DrawSuggestions;
  fFooter.DrawFG;
  if Assigned(fLockIcons) then
  begin
    fLockIcons.Statics[0].Texture.X := Button[fActions[3]].X + Theme.SongJumpto.LockedIcon.X;
    fLockIcons.Statics[0].Texture.Y := Button[fActions[3]].Y + Theme.SongJumpto.LockedIcon.Y;
    fLockIcons.Statics[1].Texture.X := Button[fActions[3]].X + Theme.SongJumpto.UnlockedIcon.X;
    fLockIcons.Statics[1].Texture.Y := Button[fActions[3]].Y + Theme.SongJumpto.UnlockedIcon.Y;
    fLockIcons.Statics[0].Visible := LibraryLockdown.Active;
    fLockIcons.Statics[1].Visible := not LibraryLockdown.Active;
    fLockIcons.DrawFG;
    Exit;
  end;
  if Theme.SongJumpto.FilterActions[3].Tex <> '' then Exit;
  // A simple vector padlock remains crisp at any screen scale.
  X := Button[fActions[3]].X + Button[fActions[3]].W * 0.25;
  Y := Button[fActions[3]].Y + Button[fActions[3]].H * 0.48;
  W := Button[fActions[3]].W * 0.5;
  H := Button[fActions[3]].H * 0.35;
  Z := Button[fActions[3]].Z + 0.004;
  Renderer.DrawQuad(X, Y, Z, W, H, 0.9, 0.9, 0.9, 1);
  Renderer.DrawQuad(X+W*0.45, Y+H*0.25, Z+0.001, W*0.1, H*0.5, 0.1, 0.1, 0.1, 1);
  Renderer.DrawLine(X+W*0.2, Y, X+W*0.2, Y-H*0.8, Z, 2, 0.9, 0.9, 0.9, 1);
  Renderer.DrawLine(X+W*0.2, Y-H*0.8, X+W*0.8, Y-H*0.8, Z, 2, 0.9, 0.9, 0.9, 1);
  if LibraryLockdown.Active then
    Renderer.DrawLine(X+W*0.8, Y-H*0.8, X+W*0.8, Y, Z, 2, 0.9, 0.9, 0.9, 1);
end;

function CompareSuggestionValues(List: TStringList; A, B: integer): integer;
begin
  Result := PtrInt(List.Objects[B]) - PtrInt(List.Objects[A]);
  if Result = 0 then Result := CompareStr(LowerCase(TransliterateToASCII(List[A])),
    LowerCase(TransliterateToASCII(List[B])));
  if Result = 0 then Result := CompareStr(List[A], List[B]);
end;

function TScreenSongJumpto.SuggestionPrefix: UTF8String;
var Q: UTF8String; I: integer;
begin
  Result := '';
  if (fFocus >= Length(fRows)) or (fRows[fFocus].Kind <> fltAge) then Exit;
  Q := Trim(fRows[fFocus].Query);
  I := Pos(':', Q);
  if I > 0 then begin Result := Copy(Q, 1, I); Delete(Q, 1, I); end;
  while (Q <> '') and (Q[1] in ['<', '>', '=']) do
  begin Result := Result + Q[1]; Delete(Q, 1, 1); end;
end;

procedure TScreenSongJumpto.UpdateSuggestions;
var Context, Query, Value, Region, Key: UTF8String;
  I, J, K, Age: integer; Song: TSong;
  Seen, Parts: TStringList; Mask: TSongFilterMask;
  Kind: TSongFilter;
  procedure AddValue(const Raw: UTF8String);
  var V: UTF8String; N: integer;
  begin
    V := Trim(Raw);
    if (V = '') or (Seen.IndexOf(V) >= 0) then Exit;
    Seen.Add(V);
    if not fValues.Find(V, N) then fValues.AddObject(V, TObject(PtrInt(1)))
    else fValues.Objects[N] := TObject(PtrInt(fValues.Objects[N]) + 1);
  end;
begin
  if (fFocus >= Length(fRows)) or (fRows[fFocus].Kind = fltAll) then
  begin fSuggestionFocus := false; Exit; end;
  Kind := fRows[fFocus].Kind;
  Region := Ini.AgeCountry;
  Query := fRows[fFocus].Query;
  if Kind = fltAge then
  begin
    I := Pos(':', Query);
    if I > 0 then Region := UpperCase(Trim(Copy(Query, 1, I - 1)));
  end;
  Context := IntToStr(fFocus) + ':' + IntToStr(Ord(Kind)) + ':' + Region;
  for I := 0 to High(fRows) do
    if I <> fFocus then Context := Context + '|' + IntToStr(Ord(fRows[I].Kind)) +
      ':' + IntToStr(Length(fRows[I].Query)) + ':' + fRows[I].Query;
  if Context <> fSuggestionContext then
  begin
    fValues.Clear;
    fValues.Sorted := true;
    fSuggestionFocus := false;
    fSuggestionQuery := #1;
    Seen := TStringList.Create;
    Parts := TStringList.Create;
    try
      Mask := CatSongs.FilterMask(fRows, fFocus);
      for I := 0 to High(CatSongs.Song) do
      begin
        Song := CatSongs.Song[I];
        if not Mask[I] then Continue;
        if fPlaylistSearch and (PlaylistMan.CurPlayList = fPlaylist) and
          (PlaylistMan.GetIndexbySongID(I) = -1) then Continue;
        Seen.Clear;
        Value := '';
        case Kind of
          fltTitle: Value := Song.Title;
          fltArtist: Value := Song.Artist;
          fltLanguage: Value := Song.Language;
          fltEdition: Value := Song.Edition;
          fltGenre: Value := Song.Genre;
          fltYear: if Song.Year > 0 then Value := IntToStr(Song.Year);
          fltCreator: Value := Song.Creator;
          fltTags: Value := Song.Tags;
          fltAge: begin Age := AgeForRegion(Song.AgeRaw, Region);
            if Age < 0 then Value := '?' else Value := IntToStr(Age); end;
        end;
        if Kind in [fltLanguage, fltEdition, fltGenre, fltTags] then
        begin
          Parts.StrictDelimiter := true;
          Parts.QuoteChar := #0;
          Parts.Delimiter := ',';
          Parts.DelimitedText := StringReplace(Value, ';', ',', [rfReplaceAll]);
          for J := 0 to Parts.Count - 1 do AddValue(Parts[J]);
        end
        else AddValue(Value);
      end;
    finally
      Seen.Free;
      Parts.Free;
    end;
    fValues.Sorted := false;
    fValues.CustomSort(@CompareSuggestionValues);
    fSuggestionContext := Context;
    fSuggestionIndex := 0;
    fSuggestionFirst := 0;
  end;
  if fSuggestionQuery = Query then Exit;
  fSuggestionQuery := Query;
  SetLength(fMatches, 0);
  fSuggestionFirst := 0;
  fSuggestionIndex := 0;
  if Kind = fltAge then Delete(Query, 1, Length(SuggestionPrefix));
  Query := LowerCase(TransliterateToASCII(Trim(Query)));
  for I := 0 to fValues.Count - 1 do
  begin
    Key := LowerCase(TransliterateToASCII(fValues[I]));
    if MatchesFilterTerms(Key, Query, false) then
    begin
      K := Length(fMatches);
      SetLength(fMatches, K + 1);
      fMatches[K] := I;
    end;
  end;
  fSuggestionIndex := EnsureRange(fSuggestionIndex, 0, Max(0, High(fMatches)));
  if Length(fMatches) = 0 then fSuggestionFocus := false;
end;

procedure TScreenSongJumpto.AcceptSuggestion;
begin
  if (fFocus >= Length(fRows)) or (fSuggestionIndex < 0) or
    (fSuggestionIndex >= Length(fMatches)) then Exit;
  fRows[fFocus].Query := SuggestionPrefix + fValues[fMatches[fSuggestionIndex]];
  Changed;
  FlushChanges;
end;

procedure TScreenSongJumpto.DrawSuggestions;
var I, N, S, MaxRows: integer; B: TThemeButton; H, Margin: single;
begin
  if (Length(fMatches) = 0) or (Length(Statics) = 0) or
    (Length(fSuggestions.Statics) = 0) then Exit;
  Margin := Theme.SongJumpto.SuggestionMargin;
  fSuggestionX := Statics[0].Texture.X + Statics[0].Texture.W + Theme.SongJumpto.SuggestionGap;
  fSuggestionW := Min(Theme.SongJumpto.SuggestionWidth, RenderW - Margin - fSuggestionX);
  if fSuggestionW < 80 then begin fSuggestionRows := 0; Exit; end;
  MaxRows := Max(1, Floor((RenderH - 2 * Margin) / Theme.SongJumpto.SuggestionRowHeight));
  fSuggestionRows := Min(Length(fMatches), MaxRows);
  H := fSuggestionRows * Theme.SongJumpto.SuggestionRowHeight;
  S := EnsureRange(fFocus - fFirst, 0, FILTER_SLOTS - 1);
  fSuggestionY := EnsureRange(Button[fInputs[S]].Y, Margin, Max(Margin, RenderH - Margin - H));
  if fSuggestionFocus then
  begin
    if fSuggestionIndex < fSuggestionFirst then fSuggestionFirst := fSuggestionIndex;
    if fSuggestionIndex >= fSuggestionFirst + fSuggestionRows then
      fSuggestionFirst := fSuggestionIndex - fSuggestionRows + 1;
  end;
  fSuggestionFirst := EnsureRange(fSuggestionFirst, 0, Max(0, Length(fMatches) - fSuggestionRows));
  fSuggestions.Statics[0].Texture.X := fSuggestionX;
  fSuggestions.Statics[0].Texture.Y := fSuggestionY;
  fSuggestions.Statics[0].Texture.W := fSuggestionW;
  fSuggestions.Statics[0].Texture.H := H;
  while fSuggestions.RowCount < fSuggestionRows do
  begin
    B := Theme.SongJumpto.SuggestionButton;
    B.Fade := false;
    B.Reflection := false;
    B.W := Round(fSuggestionW); B.SelectW := B.W;
    B.H := Theme.SongJumpto.SuggestionRowHeight; B.SelectH := B.H;
    fSuggestions.AddButton(B);
  end;
  for I := 0 to fSuggestions.RowCount - 1 do
  begin
    fSuggestions.Row(I).Visible := I < fSuggestionRows;
    if I >= fSuggestionRows then Continue;
    N := fMatches[fSuggestionFirst + I];
    with fSuggestions.Row(I) do
    begin
      X := fSuggestionX; Y := fSuggestionY + I * Theme.SongJumpto.SuggestionRowHeight;
      W := fSuggestionW; SelectW := W;
      Selected := fSuggestionFocus and (fSuggestionFirst + I = fSuggestionIndex);
      Text[0].W := W - 8;
      Text[0].H := Theme.SongJumpto.SuggestionRowHeight;
      Text[0].Writable := false;
      Text[0].Text := fValues[N] + ' (' + IntToStr(PtrInt(fValues.Objects[N])) + ')';
    end;
  end;
  fSuggestions.DrawFG;
  if Length(fMatches) > fSuggestionRows then
    Renderer.DrawLine(fSuggestionX + fSuggestionW - 3,
      fSuggestionY + H * fSuggestionFirst / Length(fMatches),
      fSuggestionX + fSuggestionW - 3,
      fSuggestionY + H * (fSuggestionFirst + fSuggestionRows) / Length(fMatches),
      Theme.SongJumpto.SuggestionPanel.Z + 0.004, 2,
      Theme.SongJumpto.FocusColor.R, Theme.SongJumpto.FocusColor.G,
      Theme.SongJumpto.FocusColor.B, Theme.SongJumpto.FocusAlpha);
end;

procedure TScreenSongJumpto.SetTextFound(Count: cardinal; SelectedSong: TSong);
var I, NewSelection: integer;
begin
  if Count = 0 then
    Text[0].Text := Theme.SongJumpto.NoSongsFound
  else
    Text[0].Text := Format(Theme.SongJumpto.SongsFound, [Count]);

  if FilterSummary = '' then
    ScreenSong.HideCatTL
  else
    ScreenSong.ShowCatTLCustom(Format(Theme.SongJumpto.CatText, [FilterSummary]));

  //Set visSongs
  fVisSongs := Count;

  // Keep the current song if it still matches; otherwise choose the first result.
  NewSelection := -1;
  for I := 0 to High(CatSongs.Song) do
    if CatSongs.Song[I].Visible then
    begin
      if NewSelection = -1 then NewSelection := I;
      if CatSongs.Song[I] = SelectedSong then
      begin
        NewSelection := I;
        Break;
      end;
    end;
  if NewSelection >= 0 then
  begin
    if TSongMenuMode(Ini.SongMenu) in [smChessboard, smList] then
      ScreenSong.SkipTo(CatSongs.VisibleIndex(NewSelection), NewSelection, Count)
    else
      ScreenSong.Interaction := NewSelection;
  end
  else
  begin
    ScreenSong.ChessboardMinLine := 0;
    ScreenSong.ListMinLine := 0;
  end;
  ScreenSong.FixSelected;

  ScreenSong.SetScrollRefresh;

  //Play Correct Music
  if (ScreenSong.Interaction <> fLastPlayed) or (CatSongs.VisibleSongs = 0) then
  begin
    if (CatSongs.VisibleSongs > 0) then
      fLastPlayed := ScreenSong.Interaction
    else
      fLastPlayed := -1;

    ScreenSong.ChangeMusic;
  end;
end;

end.
