program remote_playlist_name_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses URemoteControl;
begin
 Assert(IsValidRemotePlaylistName('Relay native test'));
 Assert(not IsValidRemotePlaylistName('Relay native test?'));
 Assert(not IsValidRemotePlaylistName('../outside'));
 Assert(not IsValidRemotePlaylistName('CON'));
 Assert(not IsValidRemotePlaylistName('COM1.txt'));
 Assert(not IsValidRemotePlaylistName('trailing.'));
 Assert(not IsValidRemotePlaylistName(''));
 WriteLn('Remote playlist filename validation passed');
end.
