program remote_media_sources_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses fpjson, URemoteMediaSources;
var Sources: TRemoteMediaSources; Songs: TJSONArray;
begin
 Sources := TRemoteMediaSources.Create; Songs := TJSONArray.Create;
 try
  Songs.Add(TJSONObject.Create(['songId', 7, 'audioPath', '/game/song.wav', 'coverPath', '/game/cover.png']));
  Sources.Replace(Songs);
  Assert(Sources.Resolve(7, 'preview') = '/game/song.wav');
  Assert(Sources.Resolve(7, 'song-preview') = '/game/song.wav');
  Assert(Sources.Resolve(7, 'game-audio') = '/game/song.wav');
  Assert(Sources.Resolve(7, 'song-cover') = '/game/cover.png');
  Assert(Sources.Resolve(7, 'device-music') = '/game/song.wav');
  Assert(Sources.Resolve(7, 'cover') = '/game/cover.png');
  Assert(Sources.Resolve(8, 'preview') = '');
  Assert(Sources.Resolve(7, '/arbitrary/file') = '');
  Songs.Clear; Sources.Replace(Songs);
  Assert(Sources.Resolve(7, 'preview') = '');
 finally Songs.Free; Sources.Free; end;
 WriteLn('Private game-owned media source lookup passed');
end.
