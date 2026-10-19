unit ULockdownUI;

{$mode delphi}

interface

uses UMenu;

procedure ToggleLibraryLockdown;
function RequestLockdownAccess(Target: PMenu): boolean;

implementation

uses Classes, SysUtils, ULibraryLockdown, UGraphic, UDisplay, ULanguage,
  UScreenPopup, UScreenSongJumpto, USongs, UPlaylist, USong, UMain, UNote;

var
  PendingTarget: PMenu;
  PendingPassword: UTF8String;
  ConfirmingPassword: boolean;

procedure RebuildLibrary;
begin
  PlaylistMan.UnsetPlaylist;
  CurrentSong := nil;
  CatSongs.Refresh;
  PlaylistMan.ReindexAllPlaylists;
  ScreenSong.GenerateThumbnails;
  ScreenSong.Interaction := 0;
  ScreenSong.ChessboardMinLine := 0;
  ScreenSong.ListMinLine := 0;
  ScreenSong.ResetRandomSongState;
  ScreenSong.OnShow;
end;

procedure PasswordAccessResult(Value: boolean; Data: Pointer);
var Password: UTF8String;
begin
  Password := ScreenPopupInsertUser.Password;
  ScreenPopupInsertUser.Password := '';
  if not Value then Exit;
  if not LibraryLockdown.CheckPassword(Password) then
  begin
    ScreenPopupError.ShowPopup(Language.Translate('LOCKDOWN_WRONG_PASSWORD'));
    Exit;
  end;
  // Authorize this one transition without releasing the library restriction.
  Display.Fade := 0;
  if PendingTarget = nil then
  begin
    Display.NextScreenWithCheck := nil;
    Display.CheckOK := true;
  end
  else Display.NextScreen := PendingTarget;
end;

function RequestLockdownAccess(Target: PMenu): boolean;
begin
  Result := not LibraryLockdown.Active;
  if Result then Exit;
  // Do not overwrite a pending password prompt with repeated close/key events.
  if ScreenPopupInsertUser.Visible then Exit;
  PendingTarget := Target;
  ScreenPopupInsertUser.ShowPasswordPrompt(
    Language.Translate('LOCKDOWN_PASSWORD'),
    Language.Translate('LOCKDOWN_ACCESS'), @PasswordAccessResult, nil);
end;

procedure TogglePasswordResult(Value: boolean; Data: Pointer);
var
  Password: UTF8String;
  Selected: TList;
  I: integer;
begin
  Password := ScreenPopupInsertUser.Password;
  ScreenPopupInsertUser.Password := '';
  if ScreenSongJumpto.Visible then StartTextInput;
  if not Value then
  begin
    PendingPassword := '';
    ConfirmingPassword := false;
    Exit;
  end;
  if LibraryLockdown.Active then
  begin
    if not LibraryLockdown.Unlock(Songs.SongList, Password) then
    begin
      ScreenPopupError.ShowPopup(Language.Translate('LOCKDOWN_WRONG_PASSWORD'));
      Exit;
    end;
    ScreenSongJumpto.Visible := false;
    ScreenSong.StopMusicPreview;
    RebuildLibrary;
    Exit;
  end;
  if not ConfirmingPassword then
  begin
    if Password = '' then
    begin
      ScreenPopupError.ShowPopup(Language.Translate('LOCKDOWN_PASSWORD_EMPTY'));
      Exit;
    end;
    PendingPassword := Password;
    ConfirmingPassword := true;
    ScreenPopupInsertUser.ShowPasswordPrompt(Language.Translate('LOCKDOWN_CONFIRM'),
      Language.Translate('LOCKDOWN_CONFIRM_HINT'), @TogglePasswordResult, nil);
    Exit;
  end;
  ConfirmingPassword := false;
  if Password <> PendingPassword then
  begin
    PendingPassword := '';
    ScreenPopupError.ShowPopup(Language.Translate('LOCKDOWN_MISMATCH'));
    Exit;
  end;
  PendingPassword := '';
  Selected := TList.Create;
  try
    for I := 0 to High(CatSongs.Song) do
      if not CatSongs.Song[I].Main and
        (CatSongs.Song[I].Visible or (CatSongs.CatNumShow = -1)) then
        Selected.Add(CatSongs.Song[I]);
    if not LibraryLockdown.Activate(Songs.SongList, Selected, Password) then
    begin
      ScreenPopupError.ShowPopup(Language.Translate('LOCKDOWN_NO_SONGS'));
      Exit;
    end;
    ScreenSongJumpto.Visible := false;
    ScreenSong.StopMusicPreview;
    RebuildLibrary;
  finally
    Selected.Free;
  end;
end;

procedure ToggleLibraryLockdown;
begin
  if Songs.Processing then Exit;
  PendingPassword := '';
  ConfirmingPassword := false;
  if LibraryLockdown.Active then
    ScreenPopupInsertUser.ShowPasswordPrompt(Language.Translate('LOCKDOWN_UNLOCK'),
      Language.Translate('LOCKDOWN_UNLOCK_HINT'), @TogglePasswordResult, nil)
  else
    ScreenPopupInsertUser.ShowPasswordPrompt(Language.Translate('LOCKDOWN_PASSWORD'),
      Language.Translate('LOCKDOWN_START_HINT'), @TogglePasswordResult, nil);
end;

end.
