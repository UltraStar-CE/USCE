unit UDuplicateSongUI;
{$mode delphi}{$codepage utf8}
interface
uses UMenu, USong, sdl2;
type
  TStartupContinuation = procedure;
  TDuplicateSongPopup = class(TMenu)
  private
    First, Second: TSong;
    fMouseInput, Changed: boolean;
    ContinueAfterCheck: TStartupContinuation;
    ErrorText: integer;
    procedure ShowPair;
    procedure Complete;
    procedure Save;
  public
    Visible: boolean;
    constructor Create; override;
    procedure Start(Continuation: TStartupContinuation);
    function Draw: boolean; override;
    function ParseInput(Key: cardinal; Ch: UCS4Char; Down: boolean;
      Repeated: boolean = false): boolean; override;
    function ParseMouse(MouseButton: integer; Down: boolean; X, Y: integer): boolean; override;
  end;
var DuplicateSongPopup: TDuplicateSongPopup;
procedure CheckStartupSongIdentities(ContinueStartup: TStartupContinuation);
implementation
uses SysUtils, USongs, USongIdentity, UGraphic, ULanguage, UScreenPopup, UPlaylist,
  UThemes, UUnicodeUtils, UMain, URenderer, UCommon;
constructor TDuplicateSongPopup.Create;
var I: integer; Basic: TThemeBasic;
begin
  inherited;
  Basic := TThemeBasic.Create;
  try
    Basic.Background := Theme.SongJumpto.Background;
    SetLength(Basic.Statics, 1); Basic.Statics[0] := Theme.DuplicateSongs.Panel;
    LoadFromTheme(Basic);
  finally Basic.Free; end;
  I := AddText(Theme.DuplicateSongs.Heading);
  Text[I].Text := Language.Translate('DUPLICATE_HEADING');
  I := AddText(Theme.DuplicateSongs.Labels[0]); Text[I].Text := Language.Translate('DUPLICATE_ARTIST');
  I := AddText(Theme.DuplicateSongs.Labels[1]); Text[I].Text := Language.Translate('DUPLICATE_TITLE');
  AddText(Theme.DuplicateSongs.Paths[0]);
  AddText(Theme.DuplicateSongs.Paths[1]);
  ErrorText := AddText(Theme.DuplicateSongs.Hint);
  for I := 0 to 3 do
  begin
    AddButton(Theme.DuplicateSongs.Inputs[I]);
    Button[I].Text[0].Writable := true;
  end;
  AddButton(Theme.DuplicateSongs.Actions[0]);
  Button[4].Text[0].Text := Language.Translate('DUPLICATE_SAVE');
  AddButton(Theme.DuplicateSongs.Actions[1]);
  Button[5].Text[0].Text := Language.Translate('DUPLICATE_START_ANYWAY');
end;
function ShortPath(Song: TSong): UTF8String;
var Value: UCS4String;
begin
  Value := UTF8ToUCS4String(Song.Path.Append(Song.FileName).ToUTF8);
  // Keep the filename and nearest folders visible, rather than an overflowing root.
  if Length(Value) > 72 then Result := '…' + UCS4ToUTF8String(Copy(Value, Length(Value) - 68, 69))
  else Result := UCS4ToUTF8String(Value);
end;
procedure TDuplicateSongPopup.Start(Continuation: TStartupContinuation);
begin
  ContinueAfterCheck := Continuation; Changed := false; ShowPair;
end;
procedure TDuplicateSongPopup.ShowPair;
begin
  if not FindDuplicateIdentity(Songs.SongList, First, Second) then begin Complete; Exit; end;
  Button[0].Text[0].Text := First.Artist;
  Button[1].Text[0].Text := First.Title;
  Button[2].Text[0].Text := Second.Artist;
  Button[3].Text[0].Text := Second.Title;
  Text[3].Text := ShortPath(First); Text[4].Text := ShortPath(Second);
  Text[ErrorText].Text := Language.Translate('DUPLICATE_HINT');
  Visible := true; Interaction := 1; StartTextInput;
end;
procedure TDuplicateSongPopup.Complete;
begin
  Visible := false; StopTextInput;
  if Changed then
  begin
    CatSongs.Refresh; PlaylistMan.ReindexAllPlaylists;
    ScreenSong.GenerateThumbnails; ScreenSong.ResetRandomSongState;
  end;
  First := nil; Second := nil;
  ContinueAfterCheck;
end;
procedure BypassConfirmed(Value: integer; Data: Pointer);
begin
  if Value = 0 then DuplicateSongPopup.Complete
  else
  begin
    // Restore the editor explicitly; dismissing the warning never authorizes startup.
    DuplicateSongPopup.Visible := true;
    DuplicateSongPopup.Interaction := 1;
    StartTextInput;
  end;
end;
procedure TDuplicateSongPopup.Save;
begin
  try
    // Rebuild dependent lists even if a later file write fails after an earlier save.
    Changed := true;
    RenameSongIdentityPair(Songs.SongList, First, Second,
      Button[0].Text[0].Text, Button[1].Text[0].Text,
      Button[2].Text[0].Text, Button[3].Text[0].Text);
    ShowPair;
  except on E: Exception do Text[ErrorText].Text := Language.Translate(E.Message); end;
end;
function TDuplicateSongPopup.ParseInput(Key: cardinal; Ch: UCS4Char; Down: boolean; Repeated: boolean): boolean;
begin
  Result := true;
  if not Down then Exit;
  if (Interaction < 4) and (Key = SDLK_a) and (SDL_GetModState and KMOD_CTRL <> 0) then
  begin Button[Interaction].Text[0].Text := ''; Exit; end;
  if (Interaction < 4) and IsPrintableChar(Ch) and (SDL_GetModState and (KMOD_CTRL or KMOD_ALT) = 0) then
  begin Button[Interaction].Text[0].Text := Button[Interaction].Text[0].Text + UCS4ToUTF8String(Ch); Exit; end;
  case Key of
    SDLK_BACKSPACE: if Interaction < 4 then Button[Interaction].Text[0].DeleteLastLetter;
    SDLK_TAB: if SDL_GetModState and KMOD_SHIFT <> 0 then InteractPrev else InteractNext;
    SDLK_UP: if Interaction in [2,3] then Interaction := Interaction - 2 else InteractPrev;
    SDLK_DOWN: if Interaction in [0,1] then Interaction := Interaction + 2 else InteractNext;
    SDLK_LEFT: InteractPrev;
    SDLK_RIGHT: InteractNext;
    SDLK_RETURN:
      if Interaction = 4 then Save
      else if Interaction = 5 then
      begin
        StopTextInput;
        ScreenPopupInfo.ShowPopup(Language.Translate('DUPLICATE_BYPASS_WARNING'),
          [Language.Translate('DUPLICATE_START_ANYWAY'), Language.Translate('DUPLICATE_GO_BACK')],
          @BypassConfirmed, nil, 1, 1);
      end
      else if not fMouseInput then InteractNext;
    SDLK_ESCAPE: begin end;
  end;
end;
function TDuplicateSongPopup.ParseMouse(MouseButton: integer; Down: boolean; X, Y: integer): boolean;
begin
  fMouseInput := true;
  try Result := inherited ParseMouse(MouseButton, Down, X, Y);
  finally fMouseInput := false; end;
end;
function TDuplicateSongPopup.Draw: boolean;
begin
  Renderer.ClearFrameBuffer(CLEAR_DEPTH);
  Result := inherited Draw;
  DrawDialogFocus;
end;
procedure CheckStartupSongIdentities(ContinueStartup: TStartupContinuation);
begin
  FreeAndNil(DuplicateSongPopup);
  DuplicateSongPopup := TDuplicateSongPopup.Create;
  DuplicateSongPopup.Start(ContinueStartup);
end;
end.
