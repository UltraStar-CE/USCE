{ Game-thread serialization of the song library, independent of the active screen.
  Private media paths stay inside the native relay and are stripped from API data. }
unit URemoteSongLibrary;
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface
uses UPath, USong;
function RemoteSongToJson(const SongIndex: integer): string;
function RemoteSongLibraryJson: string;
procedure SelectRemoteAudio(const Item: TSong; var AudioPath: IPath; var AudioSource: UTF8String);
implementation
uses Classes, SysUtils, Math, UIni, USongs, URemoteBridgeIPC;
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
  SongKey: UTF8String;
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
end.
