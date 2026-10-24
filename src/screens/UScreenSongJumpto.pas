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
    fLastPlayed, fVisSongs, fFocus, fFirst, fPlaylist, fFocusPart: integer;
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
    procedure ResetFilters;
    function Draw: boolean; override;
    property Visible: boolean read fVisible write SetVisible;
  end;

implementation

uses Math, UCommon, UDisplay, UFiles, UMusic, UGraphic, ULibraryLockdown, ULockdownUI,
  UHelp, UIni, ULanguage, ULog, UMain, UParty, URenderer, UPlaylist,
  UScreenSong, UUnicodeUtils, UPath, UMenuInteract;

const ID = 'ID_016';

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
    Input := Theme.SongJumpto.ButtonRemove;
    Inc(Input.Y, S * Theme.SongJumpto.RowSpacing);
    fRemove[S] := AddButton(Input);
  end;
  for I := 0 to 3 do
    fActions[I] := AddButton(Theme.SongJumpto.FilterActions[I]);
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
    Button[fRemove[S]].Y := Theme.SongJumpto.ButtonRemove.Y + S * Theme.SongJumpto.RowSpacing;
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
    Button[fRemove[S]].Visible := R < Length(fRows);
    SelectsS[fCategories[S]].Visible := R < Length(fRows);
    if R >= Length(fRows) then Continue;
    fSlotKinds[S] := Ord(fRows[R].Kind);
    UpdateSelectSlideOptions(fCategories[S], Theme.SongJumpto.IType, fSlotKinds[S]);
    Button[fInputs[S]].Text[0].Text := fRows[R].Query;
    Button[fInputs[S]].Selected := (fFocus = R) and (fFocusPart = 0);
    Button[fRemove[S]].Selected := (fFocus = R) and (fFocusPart = 1);
    SelectsS[fCategories[S]].Selected := (fFocus = R) and (fFocusPart = 0);
  end;
  Button[fActions[0]].Text[0].Text := '+';
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
  RefreshRows;
  SetTextFound(ApplyFilter);
  ScreenSong.NextRandomSearchIdx := CatSongs.VisibleSongs;
end;

procedure TScreenSongJumpto.AddRow;
begin
  // Reuse an empty trailing row rather than adding a series of empty rows.
  if Trim(fRows[High(fRows)].Query) <> '' then SetLength(fRows, Length(fRows) + 1);
  fFocus := High(fRows); fFocusPart := 0;
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
  fFocus := Min(Index, High(fRows)); fFocusPart := 0;
  Changed;
end;

procedure TScreenSongJumpto.ActivateAction(Action: integer);
begin
  case Action of
    0: AddRow;
    1: begin SetLength(fRows, 1); fRows[0].Query := ''; fRows[0].Kind := fltAll;
         fFocus := 0; fFirst := 0; fFocusPart := 0; Changed; end;
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
  if (fFocus < Length(fRows)) and (fFocusPart = 0) and (IsAlphaNumericChar(CharCode) or
    IsPunctuationChar(CharCode) or (CharCode = 32)) then
  begin
    fRows[fFocus].Query := fRows[fFocus].Query + UCS4ToUTF8String(CharCode);
    Changed;
    Exit;
  end;
  case PressedKey of
    SDLK_F1: ScreenPopupHelp.ShowPopup;
    SDLK_TAB:
      begin
        if (fFocus < Length(fRows)) and (fFocusPart = 0) then fFocusPart := 1
        else begin fFocusPart := 0; fFocus := (fFocus + 1) mod (Length(fRows) + 4);
          if fFocus = Length(fRows) + 2 then Inc(fFocus); end;
        RefreshRows;
      end;
    SDLK_ESCAPE: begin Visible := false; AudioPlayback.PlaySound(SoundLib.Back); end;
    SDLK_RETURN: if fFocus < Length(fRows) then
                   begin
                     if fFocusPart = 1 then RemoveRow(fFocus) else Visible := false;
                   end
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
        fFocusPart := 0;
        if (fFocus = High(fRows)) and (Trim(fRows[fFocus].Query) <> '') then AddRow
        else begin fFocus := Min(fFocus + 1, Length(fRows) + 3);
          if fFocus = Length(fRows) + 2 then Inc(fFocus); RefreshRows; end;
      end;
    SDLK_UP: begin fFocusPart := 0; fFocus := Max(0, fFocus - 1);
      if fFocus = Length(fRows) + 2 then Dec(fFocus); RefreshRows; end;
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
    Result := Button[B].Visible and (LX >= Button[B].X) and (LX <= Button[B].X + Button[B].W) and
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
    if Inside(fInputs[S]) then begin fFocus := R; fFocusPart := 0; RefreshRows; Exit; end;
    Area := SelectsS[fCategories[S]].GetMouseOverArea;
    if (LX >= Area.X) and (LX <= Area.X + Area.W) and
       (LY >= Area.Y) and (LY < Area.Y + Area.H) then
      begin
        fFocus := R; fFocusPart := 0;
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

procedure TScreenSongJumpto.ResetFilters;
begin
  // Search rows are temporary. Lockdown freezes the library, not these queries.
  SetLength(fRows, 1);
  fRows[0].Query := '';
  fRows[0].Kind := fltAll;
  fPlaylistSearch := false;
  fPlaylist := -1;
  fFocus := 0; fFirst := 0; fFocusPart := 0;
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
    ResetFilters;
    fPlaylistSearch := (CatSongs.CatNumShow = -3) and (PlaylistMan.CurPlayList <> -1);
    fPlaylist := PlaylistMan.CurPlayList;
    Text[0].Text := Format(Theme.SongJumpto.SongsFound, [CatSongs.VisibleSongs]);
  end;
  fFocus := 0; fFirst := 0; fFocusPart := 0;
  fLastPlayed := ScreenSong.Interaction;
  RefreshRows;
end;

function TScreenSongJumpto.Draw: boolean;
var I: integer; X, Y, W, H, Z: real;
  procedure Outline(B: integer);
  begin
    if not Button[B].Visible or not Button[B].Selected then Exit;
    X := Button[B].X; Y := Button[B].Y; W := Button[B].W; H := Button[B].H;
    Z := Button[B].Z + 0.003;
    Renderer.DrawLine(X, Y, X+W, Y, Z, 1.5, 0.5, 0.85, 1, 1);
    Renderer.DrawLine(X+W, Y, X+W, Y+H, Z, 1.5, 0.5, 0.85, 1, 1);
    Renderer.DrawLine(X+W, Y+H, X, Y+H, Z, 1.5, 0.5, 0.85, 1, 1);
    Renderer.DrawLine(X, Y+H, X, Y, Z, 1.5, 0.5, 0.85, 1, 1);
  end;
begin
  Renderer.ClearFrameBuffer(CLEAR_DEPTH);
  Result := inherited Draw;
  for I := 0 to FILTER_SLOTS - 1 do
  begin
    Outline(fInputs[I]); Outline(fRemove[I]);
  end;
  for I := 0 to 3 do Outline(fActions[I]);
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

procedure TScreenSongJumpto.SetTextFound(Count: cardinal);
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
