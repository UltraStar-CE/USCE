unit UDuplicateSongUI;
{$mode delphi}{$codepage utf8}
interface
uses UMenu, UDocumentUI, USong, sdl2;
type
  TStartupContinuation = procedure;
  TDuplicateSongPopup = class(TMenu)
  private
    First, Second: TSong;
    fMouseInput, Changed: boolean;
    ContinueAfterCheck: TStartupContinuation;
    ErrorText: integer;
    DocumentUI: TDocumentUI;
    Fields: array[0..3] of UTF8String;
    function Field(Index: integer): UTF8String;
    procedure SetField(Index: integer; const Value: UTF8String);
    procedure SetHint(const Value: UTF8String);
    procedure SyncDocument;
    procedure ReadDocumentSelection;
    procedure ShowPair;
    procedure Complete;
    procedure Save;
  public
    Visible: boolean;
    constructor Create; override;
    destructor Destroy; override;
    procedure SetInteraction(Num: integer); override;
    procedure InteractNext; override;
    procedure InteractPrev; override;
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
const
  uiDuplicateRole = 'duplicate-songs';
  uiDuplicateFields = 'duplicate.fields';
  uiDuplicateFocus = 'duplicate.focus';
  uiDuplicateSave = 'duplicate.save';
  uiDuplicateIgnore = 'duplicate.ignore';

function TDuplicateSongPopup.Field(Index: integer): UTF8String;
begin
  if DocumentUI<>nil then Result:=Fields[Index] else Result:=Button[Index].Text[0].Text;
end;
procedure TDuplicateSongPopup.SetField(Index: integer; const Value: UTF8String);
begin
  if DocumentUI<>nil then Fields[Index]:=Value else Button[Index].Text[0].Text:=Value;
end;
procedure TDuplicateSongPopup.SetHint(const Value: UTF8String);
begin
  if DocumentUI<>nil then DocumentUI.SetValue('duplicate.hint',Value) else Text[ErrorText].Text:=Value;
end;
procedure TDuplicateSongPopup.SetInteraction(Num: integer);
begin
  if DocumentUI=nil then inherited SetInteraction(Num)
  else if (Num>=0) and (Num<=5) then begin
    SelInteraction:=Num;
    if Visible then DocumentUI.Focus('duplicate-control-'+IntToStr(Num));
  end;
end;
procedure TDuplicateSongPopup.InteractNext;
begin
  if DocumentUI=nil then inherited else Interaction:=(Interaction+1) mod 6;
end;
procedure TDuplicateSongPopup.InteractPrev;
begin
  if DocumentUI=nil then inherited else Interaction:=(Interaction+5) mod 6;
end;
procedure TDuplicateSongPopup.ReadDocumentSelection;
var Selected:integer;
begin
  if TryStrToInt(DocumentUI.FocusedTarget,Selected) then Interaction:=Selected;
end;
procedure TDuplicateSongPopup.SyncDocument;
var I:integer; Prefix:UTF8String;
begin
  DocumentUI.SetArray(uiDuplicateFields,4);
  for I:=0 to 3 do begin
    Prefix:=uiDuplicateFields+'['+IntToStr(I)+'].';
    DocumentUI.SetModel(Prefix+'id',IntToStr(I),1);
    DocumentUI.SetModel(Prefix+'value',Fields[I]);
    DocumentUI.SetModel(Prefix+'selected',IntToStr(Ord(Interaction=I)),2);
  end;
  DocumentUI.PrepareLayout;
  DocumentUI.Focus('duplicate-control-'+IntToStr(Interaction));
  if Interaction<4 then DocumentUI.Reveal('duplicate-caret-'+IntToStr(Interaction));
end;
destructor TDuplicateSongPopup.Destroy;
begin DocumentUI.Free; inherited; end;
constructor TDuplicateSongPopup.Create;
var I: integer; Basic: TThemeBasic;
begin
  inherited;
  DocumentUI:=TDocumentUI.Open(uiDuplicateRole,uiDuplicateFields);
  if DocumentUI<>nil then Exit;
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
  SetField(0,First.Artist); SetField(1,First.Title);
  SetField(2,Second.Artist); SetField(3,Second.Title);
  if DocumentUI<>nil then begin
    DocumentUI.SetValue('duplicate.path1',ShortPath(First)); DocumentUI.SetValue('duplicate.path2',ShortPath(Second));
  end else begin Text[3].Text := ShortPath(First); Text[4].Text := ShortPath(Second); end;
  SetHint(Language.Translate('DUPLICATE_HINT'));
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
      Field(0), Field(1), Field(2), Field(3));
    ShowPair;
  except on E: Exception do SetHint(Language.Translate(E.Message)); end;
end;
function TDuplicateSongPopup.ParseInput(Key: cardinal; Ch: UCS4Char; Down: boolean; Repeated: boolean): boolean;
begin
  Result := true;
  if not Down then Exit;
  if DocumentUI<>nil then ReadDocumentSelection;
  if (Interaction < 4) and (Key = SDLK_a) and (SDL_GetModState and KMOD_CTRL <> 0) then
  begin SetField(Interaction,''); Exit; end;
  if (Interaction < 4) and IsPrintableChar(Ch) and (SDL_GetModState and (KMOD_CTRL or KMOD_ALT) = 0) then
  begin SetField(Interaction,Field(Interaction)+UCS4ToUTF8String(Ch)); Exit; end;
  case Key of
    SDLK_BACKSPACE: if Interaction < 4 then SetField(Interaction,UTF8Copy(Field(Interaction),1,LengthUTF8(Field(Interaction))-1));
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
var Action:UTF8String; Selected:integer;
begin
  if DocumentUI<>nil then begin
    if MouseButton=SDL_BUTTON_LEFT then DocumentUI.Mouse(X,Y,0,Down) else DocumentUI.Mouse(X,Y);
    ReadDocumentSelection; Action:=DocumentUI.TakeAction; Result:=true;
    if Action=uiDuplicateFocus then begin
      if TryStrToInt(DocumentUI.ActionTarget,Selected) and (Selected>=0) and (Selected<=3) then Interaction:=Selected;
    end else if Action=uiDuplicateSave then begin Interaction:=4; Result:=ParseInput(SDLK_RETURN,0,true); end
    else if Action=uiDuplicateIgnore then begin Interaction:=5; Result:=ParseInput(SDLK_RETURN,0,true); end;
    Exit;
  end;
  fMouseInput := true;
  try Result := inherited ParseMouse(MouseButton, Down, X, Y);
  finally fMouseInput := false; end;
end;
function TDuplicateSongPopup.Draw: boolean;
begin
  Renderer.ClearFrameBuffer(CLEAR_DEPTH);
  if DocumentUI<>nil then begin SyncDocument; Exit(DocumentUI.Draw(false,true)); end;
  Result := inherited Draw;
end;
procedure CheckStartupSongIdentities(ContinueStartup: TStartupContinuation);
begin
  FreeAndNil(DuplicateSongPopup);
  DuplicateSongPopup := TDuplicateSongPopup.Create;
  DuplicateSongPopup.Start(ContinueStartup);
end;
end.
