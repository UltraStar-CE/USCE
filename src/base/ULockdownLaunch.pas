unit ULockdownLaunch;
{$mode delphi}{$codepage utf8}
interface
uses Classes, UPlaylist, USong;
function CollectLaunchSongs(const Names: array of UTF8String;
  const Playlists: APlaylist; const LibrarySongs: array of TSong;
  Selected: TList; out Error: UTF8String): boolean;
implementation
uses SysUtils, UUnicodeUtils;
function CollectLaunchSongs(const Names: array of UTF8String;
  const Playlists: APlaylist; const LibrarySongs: array of TSong;
  Selected: TList; out Error: UTF8String): boolean;
var N, P, I, Index, Match: integer;
begin
  Result := false;
  Error := '';
  Selected.Clear;
  for N := 0 to High(Names) do
  begin
    Match := -1;
    for P := 0 to High(Playlists) do
      if WideCompareText(UTF8Decode(Names[N]), UTF8Decode(Playlists[P].Name)) = 0 then
      begin
        if Match <> -1 then begin Error := 'Ambiguous playlist: ' + Names[N]; Exit; end;
        Match := P;
      end;
    if Match = -1 then begin Error := 'Playlist not found: ' + Names[N]; Exit; end;
    for I := 0 to High(Playlists[Match].Items) do
    begin
      Index := Playlists[Match].Items[I].SongID;
      if (Index < 0) or (Index >= Length(LibrarySongs)) then Continue;
      if LibrarySongs[Index].Main then Continue;
      if Selected.IndexOf(LibrarySongs[Index]) = -1 then Selected.Add(LibrarySongs[Index]);
    end;
  end;
  Result := Selected.Count > 0;
  if not Result then Error := 'Selected playlists contain no available songs';
end;
end.
