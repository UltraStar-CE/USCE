unit UDuplicateSongUI;
{$mode delphi}{$codepage utf8}
interface
type TStartupContinuation = procedure;
procedure CheckStartupSongIdentities(ContinueStartup: TStartupContinuation);
implementation
uses SysUtils, USong, USongs, USongIdentity, UGraphic, ULanguage, UScreenPopup, UPlaylist;
var ContinueAfterCheck: TStartupContinuation; First, Second, Editing: TSong;
  ArtistValue, TitleValue: UTF8String; Changed: boolean;
procedure ShowPair; forward;
procedure ShowEditor; forward;
procedure Complete;
begin
  if Changed then
  begin
    CatSongs.Refresh;
    PlaylistMan.ReindexAllPlaylists;
    ScreenSong.GenerateThumbnails;
    ScreenSong.ResetRandomSongState;
  end;
  First := nil; Second := nil; Editing := nil;
  ContinueAfterCheck;
end;
procedure BypassConfirmed(Value: boolean; Data: Pointer);
begin
  if Value then Complete else ShowPair;
end;
procedure RetryEdit(Value: integer; Data: Pointer);
begin ShowEditor; end;
procedure Edited(Value: boolean; Data: Pointer);
begin
  ArtistValue := ScreenPopupInsertUser.Username;
  TitleValue := ScreenPopupInsertUser.Password;
  ScreenPopupInsertUser.Password := '';
  if not Value then begin ShowPair; Exit; end;
  try
    RenameSongIdentity(Songs.SongList, Editing, ArtistValue, TitleValue);
    Changed := true;
    ShowPair;
  except on E: Exception do
    ScreenPopupError.ShowPopup(Language.Translate(E.Message),
      [Language.Translate('SONG_MENU_YES')], @RetryEdit, nil, 0, 0);
  end;
end;
procedure ShowEditor;
begin
  ScreenPopupInsertUser.ShowIdentityPrompt(Language.Translate('DUPLICATE_EDIT'),
    Language.Translate('DUPLICATE_EDIT_HINT'), ArtistValue, TitleValue, @Edited, nil);
end;
procedure PairAction(Value: integer; Data: Pointer);
begin
  if Value = 2 then
  begin
    ScreenPopupCheck.ShowPopup(Language.Translate('DUPLICATE_BYPASS_WARNING'),
      @BypassConfirmed, nil, false);
    Exit;
  end;
  if Value < 0 then begin ShowPair; Exit; end;
  if Value = 0 then Editing := First else Editing := Second;
  ArtistValue := Editing.Artist; TitleValue := Editing.Title;
  ShowEditor;
end;
procedure ShowPair;
var Message: UTF8String;
begin
  if not FindDuplicateIdentity(Songs.SongList, First, Second) then begin Complete; Exit; end;
  Message := Format(Language.Translate('DUPLICATE_FOUND'), [First.Artist, First.Title,
    First.Path.Append(First.FileName).ToUTF8, Second.Path.Append(Second.FileName).ToUTF8]);
  ScreenPopupInfo.ShowPopup(Message,
    [Language.Translate('DUPLICATE_EDIT_FIRST'), Language.Translate('DUPLICATE_EDIT_SECOND'),
     Language.Translate('DUPLICATE_START_ANYWAY')], @PairAction, nil, 0, -1);
end;
procedure CheckStartupSongIdentities(ContinueStartup: TStartupContinuation);
begin
  ContinueAfterCheck := ContinueStartup;
  Changed := false;
  ShowPair;
end;
end.
