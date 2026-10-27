{ Game-thread serialization of the song library, independent of the active screen.
  Private media paths stay inside the native relay and are stripped from API data. }
unit URemoteSongLibrary;
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface
uses UPath, USong;
function RemoteSongToJson(const SongIndex: integer): string;
function RemoteSongLibraryJson: string;
function RemotePlaylistFieldsJson: string;
procedure SelectRemoteAudio(const Item: TSong; var AudioPath: IPath; var AudioSource: UTF8String);
implementation
uses Classes, SysUtils, Math, sha1, UIni, USongs, UPlaylist, URemoteBridgeIPC;
function BoolJson(Value: boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
end;
function UseInstrumentalAudio(const Item: TSong): boolean;
var
  AudioVolume: integer;
  VocalsVolume: integer;
  RegularVolume: integer;
  InstrumentalVolume: integer;
begin
  Result := false;
  if not Assigned(Item) then
    Exit;
  if (not Assigned(Item.Karaoke)) or (Item.Karaoke = PATH_NONE) then
    Exit;
  if not Item.Path.Append(Item.Karaoke).IsFile then
    Exit;

  AudioVolume := EnsureRange(Ini.AudioVolume, 0, 100);
  VocalsVolume := EnsureRange(Ini.VocalsVolume, 0, 100);
  RegularVolume := AudioVolume * VocalsVolume;
  InstrumentalVolume := AudioVolume * (100 - VocalsVolume);
  Result := InstrumentalVolume > RegularVolume;
end;

procedure SelectRemoteAudio(const Item: TSong; var AudioPath: IPath; var AudioSource: UTF8String);
begin
  if UseInstrumentalAudio(Item) then
  begin
    AudioPath := Item.Path.Append(Item.Karaoke);
    AudioSource := 'instrumental';
  end
  else
  begin
    AudioPath := Item.Path.Append(Item.Audio);
    AudioSource := 'audio';
  end;
end;

function RemoteSongToJson(const SongIndex: integer): string;
var
  Item: TSong;
  AudioPath: IPath;
  AudioSource: UTF8String;
  SongKey, CatalogKey: UTF8String;
  SearchText: UTF8String;
begin
  Result := 'null';
  if (SongIndex < 0) or (SongIndex > High(CatSongs.Song)) then
    Exit;
  Item := CatSongs.Song[SongIndex];
  if not Assigned(Item) then
    Exit;

  SelectRemoteAudio(Item, AudioPath, AudioSource);
  SongKey := LowerCase(Item.Artist + ' - ' + Item.Title);
  // Stable within this game installation, without exposing the song file path.
  CatalogKey := SHA1Print(SHA1String(Item.Path.Append(Item.FileName).ToUTF8(false)));
  SearchText := Trim(
    Item.ArtistASCII + ' ' +
    Item.TitleASCII + ' ' +
    Item.CreatorASCII + ' ' +
    Item.GenreASCII + ' ' +
    Item.EditionASCII + ' ' +
    Item.LanguageASCII + ' ' +
    Item.TagsASCII + ' ' +
    IntToStr(Item.Year));

  Result :=
    '{"songId":' + IntToStr(SongIndex) +
    ',"songKey":"' + RemoteJsonEscape(SongKey) + '"' +
    ',"catalogKey":"' + CatalogKey + '"' +
    ',"artist":"' + RemoteJsonEscape(Item.Artist) + '"' +
    ',"title":"' + RemoteJsonEscape(Item.Title) + '"' +
    ',"year":' + IntToStr(Item.Year) +
    ',"creator":"' + RemoteJsonEscape(Item.Creator) + '"' +
    ',"genre":"' + RemoteJsonEscape(Item.Genre) + '"' +
    ',"edition":"' + RemoteJsonEscape(Item.Edition) + '"' +
    ',"language":"' + RemoteJsonEscape(Item.Language) + '"' +
    ',"tags":"' + RemoteJsonEscape(Item.Tags) + '"' +
    ',"searchText":"' + RemoteJsonEscape(SearchText) + '"' +
    ',"visible":' + BoolJson(Item.Visible) +
    ',"category":' + BoolJson(Item.Main) +
    ',"duet":' + BoolJson(Item.isDuet) +
    ',"previewStart":' + StringReplace(FloatToStr(Item.PreviewStart), ',', '.', []) +
    ',"audioSource":"' + RemoteJsonEscape(AudioSource) + '"' +
    ',"audioPath":"' + RemoteJsonEscape(UTF8String(AudioPath.ToNative)) + '"' +
    '}';
end;
function RemoteSongLibraryJson: string;
var Stream: TStringStream; I, Sent: integer;
begin
  Stream := TStringStream.Create('');
  try
    Stream.WriteString('[');
    Sent := 0;
    if Assigned(CatSongs) then
      for I := 0 to High(CatSongs.Song) do
        if Assigned(CatSongs.Song[I]) and (not CatSongs.Song[I].Main) then
        begin
          if Sent > 0 then Stream.WriteString(',');
          Stream.WriteString(RemoteSongToJson(I));
          Inc(Sent);
        end;
    Stream.WriteString(']');
    Result := Stream.DataString;
  finally Stream.Free; end;
end;
function RemotePlaylistFieldsJson: string;
var
  PlaylistIndex, CurrentPlaylist, PlaylistItemIndex, PlaylistSongId, Sent, ItemIndex: integer;
  PlaylistsJson, PlaylistItemsJson: string;
  PlaylistAudioPath: IPath;
  PlaylistAudioSource: UTF8String;
begin
  if not Assigned(PlaylistMan) then
    Exit(',"playlists":[],"playlistItems":[],"curPlaylist":-1');
  PlaylistsJson := '[';
  for PlaylistIndex := 0 to High(PlaylistMan.Playlists) do
  begin
    if PlaylistIndex > 0 then
      PlaylistsJson := PlaylistsJson + ',';
    PlaylistsJson := PlaylistsJson +
      '{"index":' + IntToStr(PlaylistIndex) +
      ',"name":"' + RemoteJsonEscape(PlaylistMan.Playlists[PlaylistIndex].Name) + '"' +
      ',"size":' + IntToStr(Length(PlaylistMan.Playlists[PlaylistIndex].Items)) +
      ',"current":' + BoolJson(PlaylistIndex = PlaylistMan.CurPlaylist) +
      ',"fixedOrder":' + BoolJson(PlaylistMan.Playlists[PlaylistIndex].FixedOrder) +
      ',"items":[';
    for ItemIndex := 0 to High(PlaylistMan.Playlists[PlaylistIndex].Items) do
    begin
      if ItemIndex > 0 then PlaylistsJson := PlaylistsJson + ',';
      PlaylistsJson := PlaylistsJson + '{"itemIndex":' + IntToStr(ItemIndex) +
        ',"songId":' + IntToStr(PlaylistMan.Playlists[PlaylistIndex].Items[ItemIndex].SongID) + '}';
    end;
    PlaylistsJson := PlaylistsJson + ']}';
  end;
  PlaylistsJson := PlaylistsJson + ']';

  CurrentPlaylist := PlaylistMan.CurPlaylist;
  PlaylistItemsJson := '[';
  if (CurrentPlaylist >= 0) and (CurrentPlaylist <= High(PlaylistMan.Playlists)) then
  begin
    Sent := 0;
    for PlaylistItemIndex := 0 to High(PlaylistMan.Playlists[CurrentPlaylist].Items) do
    begin
      if Sent > 0 then
        PlaylistItemsJson := PlaylistItemsJson + ',';
      PlaylistItemsJson := PlaylistItemsJson +
        '{"itemIndex":' + IntToStr(PlaylistItemIndex) +
        ',"songId":' + IntToStr(PlaylistMan.Playlists[CurrentPlaylist].Items[PlaylistItemIndex].SongID) +
        ',"artist":"' + RemoteJsonEscape(PlaylistMan.Playlists[CurrentPlaylist].Items[PlaylistItemIndex].Artist) + '"' +
        ',"title":"' + RemoteJsonEscape(PlaylistMan.Playlists[CurrentPlaylist].Items[PlaylistItemIndex].Title) + '"';
      PlaylistSongId := PlaylistMan.Playlists[CurrentPlaylist].Items[PlaylistItemIndex].SongID;
      if (PlaylistSongId >= 0) and
         (PlaylistSongId <= High(CatSongs.Song)) and
         Assigned(CatSongs.Song[PlaylistSongId]) then
      begin
        SelectRemoteAudio(CatSongs.Song[PlaylistSongId], PlaylistAudioPath, PlaylistAudioSource);
        PlaylistItemsJson := PlaylistItemsJson +
          ',"previewStart":' + StringReplace(FloatToStr(CatSongs.Song[PlaylistSongId].PreviewStart), ',', '.', []) +
          ',"audioSource":"' + RemoteJsonEscape(PlaylistAudioSource) + '"' +
          ',"audioPath":"' + RemoteJsonEscape(UTF8String(PlaylistAudioPath.ToNative)) + '"';
      end;
      PlaylistItemsJson := PlaylistItemsJson + '}';
      Inc(Sent);
      if Sent >= 50 then
        Break;
    end;
  end;
  PlaylistItemsJson := PlaylistItemsJson + ']';

  Result := ',"playlists":' + PlaylistsJson + ',"playlistItems":' + PlaylistItemsJson +
    ',"curPlaylist":' + IntToStr(PlaylistMan.CurPlaylist);
end;
end.
