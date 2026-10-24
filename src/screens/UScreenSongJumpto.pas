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

uses UMenu, USongs, UThemes, sdl2, SysUtils;

const FILTER_SLOTS = 3;

type
  TScreenSongJumpto = class(TMenu)
  private
    fVisible, fPlaylistSearch: boolean;
    fLastPlayed, fVisSongs, fFocus, fFirst, fPlaylist: integer;
    fRows: TSongFilterRows;
    fSlotKinds: array[0..FILTER_SLOTS-1] of integer;
    fInputs, fRemove, fCategories: array[0..FILTER_SLOTS-1] of integer;
    fActions: array[0..3] of integer;
    procedure SetVisible(Value: boolean);
    procedure SetTextFound(Count: cardinal);
    function ApplyFilter: cardinal;
    function FilterSummary: UTF8String;
    procedure RefreshRows;
    procedure Changed;
    procedure AddRow;
    procedure RemoveRow(Index: integer);
    procedure ActivateAction(Action: integer);
  public
    constructor Create; override;
    function ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    procedure OnShow; override;
    function Draw: boolean; override;
    property Visible: boolean read fVisible write SetVisible;
  end;

implementation

uses Math, UCommon, UDisplay, UFiles, UMusic, UGraphic, ULibraryLockdown, ULockdownUI,
  UHelp, UIni, ULanguage, ULog, UMain, UParty, URenderer, UPlaylist,
  UScreenSong, UUnicodeUtils, UPath, UMenuInteract;

const ID = 'ID_016';

constructor TScreenSongJumpto.Create;
var S, B, I: integer; Category: TThemeSelectSlide; Input: TThemeButton;
    TopY, BottomY: real;
begin
  inherited Create;
  AddText(Theme.SongJumpto.TextFound);
  LoadFromTheme(Theme.SongJumpto);
  TopY := Theme.SongJumpto.SelectSlideType.Y;
  for S := 0 to FILTER_SLOTS - 1 do
  begin
    Category := Theme.SongJumpto.SelectSlideType;
    Category.Y := Round(TopY + S * 78);
    fCategories[S] := AddSelectSlide(Category, fSlotKinds[S], Theme.SongJumpto.IType);
    Input := Theme.SongJumpto.ButtonSearchText;
    Input.Y := Category.Y + 28;
    Input.H := 38;
    Input.W := Input.W - 30;
    Input.SelectW := Input.W;
    Input.SelectH := Input.H;
    Input.Fade := false;
    fInputs[S] := AddButton(Input);
    B := fInputs[S];
    if Length(Button[B].Text) = 0 then AddButtonText(4, 0, '');
    Button[B].Text[0].Size := 24;
    Button[B].Text[0].Writable := true;
    fRemove[S] := AddButton(Input.X + Input.W + 2, Input.Y, 28, 38, PATH_NONE);
    AddButtonText(6, 3, 1, 1, 1, 'x');
    Button[fRemove[S]].Z := Input.Z;
    Button[fRemove[S]].Text[0].Z := Input.Z + 0.001;
    Button[fRemove[S]].Text[0].Size := 24;
  end;
  BottomY := TopY + FILTER_SLOTS * 78;
  Text[0].Y := BottomY;
  for I := 0 to 3 do
  begin
    fActions[I] := AddButton(Theme.SongJumpto.ButtonSearchText.X,
      BottomY + 28 + I * 30, Theme.SongJumpto.ButtonSearchText.W, 28, PATH_NONE);
    AddButtonText(4, 1, 1, 1, 1, '');
    Button[fActions[I]].Z := Theme.SongJumpto.ButtonSearchText.Z;
    Button[fActions[I]].Text[0].Z := Theme.SongJumpto.ButtonSearchText.Z + 0.001;
    Button[fActions[I]].Text[0].Size := 20;
  end;
  for I := 0 to High(Statics) do
    if (Statics[I].Texture.Y <= TopY) and
       (Statics[I].Texture.Y + Statics[I].Texture.H >= TopY) then
      Statics[I].Texture.H := BottomY + 156 - Statics[I].Texture.Y;
  SetLength(fRows, 1);
  fPlaylist := -1;
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
var S, R, I: integer;
begin
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
    Button[fRemove[S]].Visible := R < Length(fRows);
    SelectsS[fCategories[S]].Visible := R < Length(fRows);
    if R >= Length(fRows) then Continue;
    fSlotKinds[S] := Ord(fRows[R].Kind);
    UpdateSelectSlideOptions(fCategories[S], Theme.SongJumpto.IType, fSlotKinds[S]);
    Button[fInputs[S]].Text[0].Text := fRows[R].Query;
    Button[fInputs[S]].Selected := fFocus = R;
    SelectsS[fCategories[S]].Selected := fFocus = R;
  end;
  Button[fActions[0]].Text[0].Text := Language.Translate('FILTER_ADD');
  Button[fActions[1]].Text[0].Text := Language.Translate('FILTER_CLEAR');
  Button[fActions[2]].Text[0].Text := Language.Translate('FILTER_DONE');
  if LibraryLockdown.Active then
    Button[fActions[3]].Text[0].Text := Language.Translate('LOCKDOWN_UNLOCK')
  else Button[fActions[3]].Text[0].Text := Language.Translate('LOCKDOWN_START');
  for I := 0 to 3 do Button[fActions[I]].Selected := fFocus = Length(fRows) + I;
end;

procedure TScreenSongJumpto.Changed;
begin
  RefreshRows;
  SetTextFound(ApplyFilter);
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
    3: ToggleLibraryLockdown;
  end;
end;

function TScreenSongJumpto.ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean = false): boolean;
var S: integer;
begin
  Result := true;
  if not PressedDown then Exit;
  if (fFocus < Length(fRows)) and (IsAlphaNumericChar(CharCode) or
    IsPunctuationChar(CharCode) or (CharCode = 32)) then
  begin
    fRows[fFocus].Query := fRows[fFocus].Query + UCS4ToUTF8String(CharCode);
    Changed;
    Exit;
  end;
  case PressedKey of
    SDLK_TAB: ScreenPopupHelp.ShowPopup;
    SDLK_ESCAPE: begin Visible := false; AudioPlayback.PlaySound(SoundLib.Back); end;
    SDLK_RETURN: if fFocus < Length(fRows) then Visible := false
                 else ActivateAction(fFocus - Length(fRows));
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
      begin
        if Repeated then Exit;
        if (fFocus = High(fRows)) and (Trim(fRows[fFocus].Query) <> '') then AddRow
        else begin fFocus := Min(fFocus + 1, Length(fRows) + 3); RefreshRows; end;
      end;
    SDLK_UP: begin fFocus := Max(0, fFocus - 1); RefreshRows; end;
    SDLK_LEFT, SDLK_RIGHT:
      if fFocus < Length(fRows) then
      begin
        S := Ord(fRows[fFocus].Kind);
        if PressedKey = SDLK_LEFT then S := (S + Ord(High(TSongFilter))) mod (Ord(High(TSongFilter)) + 1)
        else S := (S + 1) mod (Ord(High(TSongFilter)) + 1);
        fRows[fFocus].Kind := TSongFilter(S);
        Changed;
      end;
  end;
end;

function TScreenSongJumpto.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var S, R, I: integer; LX, LY: real; Area: TMouseOverRect;
  function Inside(B: integer): boolean;
  begin
    Result := (LX >= Button[B].X) and (LX <= Button[B].X + Button[B].W) and
      (LY >= Button[B].Y) and (LY <= Button[B].Y + Button[B].H);
  end;
begin
  Result := true;
  if not BtnDown then Exit;
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
    if Inside(fRemove[S]) then begin RemoveRow(R); Exit; end;
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
  if not fVisible and Value then OnShow;
  SetTextInput(Value);
  fVisible := Value;
end;

procedure TScreenSongJumpto.OnShow;
var Country: UTF8String;
begin
  inherited;
  Help.SetHelpID(ID);
  Country := Ini.AgeCountry;
  if Country = '' then Country := Language.Translate('OPTION_VALUE_AGE_DEFAULT');
  Theme.SongJumpto.IType[9] := Language.Translate('SONG_JUMPTO_TYPE10') + ' (' + Country + ')';
  if CatSongs.CatNumShow <> -2 then
  begin
    SetLength(fRows, 1); fRows[0].Query := ''; fRows[0].Kind := fltAll;
    fPlaylistSearch := (CatSongs.CatNumShow = -3) and (PlaylistMan.CurPlayList <> -1);
    fPlaylist := PlaylistMan.CurPlayList;
    Text[0].Text := Format(Theme.SongJumpto.SongsFound, [CatSongs.VisibleSongs]);
  end;
  fFocus := 0; fFirst := 0;
  fLastPlayed := ScreenSong.Interaction;
  RefreshRows;
end;

function TScreenSongJumpto.Draw: boolean;
begin
  Renderer.ClearFrameBuffer(CLEAR_DEPTH);
  Result := inherited Draw;
end;

procedure TScreenSongJumpto.SetTextFound(Count: cardinal);
begin
  if (Count = 0) then
  begin
    Text[0].Text := Theme.SongJumpto.NoSongsFound;
    if (Length(FilterSummary) = 0) then
      ScreenSong.HideCatTL
    else
      ScreenSong.ShowCatTLCustom(Format(Theme.SongJumpto.CatText, [FilterSummary]));
  end
  else
  begin
    Text[0].Text := Format(Theme.SongJumpto.SongsFound, [Count]);

    //Set CatTopLeftText
    ScreenSong.ShowCatTLCustom(Format(Theme.SongJumpto.CatText, [FilterSummary]));
  end;

  //Set visSongs
  fVisSongs := Count;

  //Fix SongSelection
  if (TSongMenuMode(Ini.SongMenu) = smRoulette) then
  begin
    ScreenSong.Interaction := high(CatSongs.Song);
  end;

  if (TSongMenuMode(Ini.SongMenu) in [smChessboard, smList]) then
  begin
    ScreenSong.Interaction := 0;
    ScreenSong.ChessboardMinLine := 0;
    ScreenSong.ListMinLine := 0;
  end;

  ScreenSong.SelectNext;
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
