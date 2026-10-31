program relay_protocol_test;
{$MODE Delphi}{$H+}{$ASSERTIONS ON}
uses Classes, SysUtils, base64, fpjson, jsonparser, URemoteRelayProtocol;
type
  TProbe = class
    Sent, Received: TJSONArray;
    constructor Create;
    destructor Destroy; override;
    function Send(Message: TJSONObject): boolean;
    procedure Receive(Message: TJSONObject);
    function Last: TJSONObject;
  end;
constructor TProbe.Create;
begin inherited; Sent := TJSONArray.Create; Received := TJSONArray.Create; end;
destructor TProbe.Destroy;
begin Sent.Free; Received.Free; inherited; end;
function TProbe.Send(Message: TJSONObject): boolean;
begin Sent.Add(Message.Clone); Result := true; end;
procedure TProbe.Receive(Message: TJSONObject);
begin Received.Add(Message.Clone); end;
function TProbe.Last: TJSONObject;
begin Result := TJSONObject(Received.Items[Received.Count-1]); end;
function TestClock: int64;
begin Result := 123456789; end;
var Adapter: TRemoteRelayProtocol;
    Probe: TProbe;
    Data: TJSONData;
    I, Before: integer;
    MediaPath: string; FileStream: TFileStream; Payload: RawByteString; Snapshot: TJSONObject;

procedure Relay(const Text: string);
begin
  Data := GetJSON(Text);
  try Adapter.FromRelay(TJSONObject(Data)); finally Data.Free; end;
end;
procedure Game(const Text: string);
begin
  Data := GetJSON(Text);
  try Assert(Adapter.FromGame(TJSONObject(Data))); finally Data.Free; end;
end;

begin
  Adapter := TRemoteRelayProtocol.Create;
  Probe := TProbe.Create;
  try
    Adapter.OnSend := Probe.Send;
    Adapter.OnGame := Probe.Receive;
    Adapter.Clock := TestClock;
    Game('{"type":"song.library","library":[{"songId":3,"title":"Startup song","audioPath":"private.wav"}],"playlists":[{"index":0,"name":"Startup list","size":0}],"playlistItems":[]}');
    Assert(Adapter.Songs.Count = 1, 'Generic API must be ready without opening song selection');
    Assert(Probe.Sent.Count = 0, 'Private library snapshots must never be broadcast');
    Game('{"type":"game.state","state":"player_setup","songSeq":0}');
    Assert(Probe.Sent.Count = 0, 'Disconnected state must wait for registration');
    Relay('{"type":"room.created","roomId":"room","displayCode":"TEST","hostToken":"private"}');
    Assert(Probe.Last.Find('hostToken') = nil, 'Credentials must stay in session');
    Assert(TJSONObject(Probe.Sent.Items[0]).Get('state', '') = 'player_setup');
    Relay('{"type":"player.joined","playerId":"phone","name":"Daniel","slot":1,"difficulty":2,"avatarFile":"phone.jpg","role":"controller"}');
    Relay('{"type":"control.command","playerId":"phone","commandId":40,"command":"song.list","args":{"offset":0,"limit":10}}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('accepted', false));
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Objects['data'].Arrays['songs'].Objects[0].Get('title', '') = 'Startup song',
      'Queries before song selection must return the startup snapshot');
    Assert(Pos('private.wav', Probe.Sent.AsJSON) = 0, 'Startup paths must not leave the game');
    Relay('{"type":"player.assigned","playerId":"phone","slot":2}');
    Assert(Probe.Last.Get('slot', 0) = 2);
    Assert(Probe.Last.Get('name', '') = 'Daniel');
    Assert(Probe.Last.Get('difficulty', 0) = 2);
    Assert(Probe.Last.Get('avatarFile', '') = 'phone.jpg');
    Relay('{"type":"control.command","playerId":"phone","command":"game.pause","commandId":7}');
    Assert(Probe.Last.Get('slot', 0) = 2);
    Assert(Probe.Last.Get('role', '') = 'controller');
    Relay('{"type":"settings.update","playerId":"phone","settings":{"micDelayMs":20}}');
    Assert(Probe.Last.Get('slot', 0) = 2);
    Before := Probe.Received.Count;
    Relay('{"type":"game.state","state":"lobby","songSeq":0}');
    Assert(Probe.Received.Count = Before, 'Server roster cannot drive game screen');
    Before := Probe.Sent.Count;
    Relay('{"type":"song.state.request"}');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Get('state', '') = 'player_setup');
    Assert(TJSONObject(Probe.Sent.Items[Before+1]).Get('type', '') = 'continuous.state');
    Assert(not TJSONObject(Probe.Sent.Items[Before+1]).Get('active', true));
    Inc(Before);
    Assert(TJSONObject(Probe.Sent.Items[Before+1]).Get('type', '') = 'api.state');
    Assert(TJSONObject(Probe.Sent.Items[Before+1]).Arrays['playlists'].Objects[0].Get('name', '') = 'Startup list');
    Assert(TJSONObject(Probe.Sent.Items[Before+1]).Find('library') = nil);
    Assert(Pos('private.wav', Probe.Sent.Items[Before+1].AsJSON) = 0);

    Game('{"type":"song.select.state","playlists":[{"index":0,"name":"Old list"}]}');
    Before := Probe.Sent.Count;
    Game('{"type":"playlist.library","playlists":[{"index":0,"name":"Updated list","fixedOrder":true,"items":[{"itemIndex":0,"songId":3}]}],"curPlaylist":-1}');
    Assert(Probe.Sent.Count = Before + 1, 'Metadata edits send only the API update');
    Assert(Adapter.Songs.Count = 1, 'Playlist edits preserve the song snapshot');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Get('type', '') = 'api.state');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Arrays['playlists'].Objects[0].Get('fixedOrder', false));
    Assert(TJSONObject(Probe.Sent.Items[Before]).Arrays['playlists'].Objects[0].Arrays['items'].Objects[0].Get('songId', -1) = 3);
    Relay('{"type":"control.command","playerId":"phone","commandId":41,"command":"song.list","args":{"offset":0,"limit":10}}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Objects['data'].Arrays['songs'].Objects[0].Get('title', '') = 'Startup song');

    Before := Probe.Sent.Count;
    Relay('{"type":"song.state.request"}');
    for I := Before to Probe.Sent.Count - 1 do
      if TJSONObject(Probe.Sent.Items[I]).Get('type', '') = 'song.select.state' then
        Assert(TJSONObject(Probe.Sent.Items[I]).Arrays['playlists'].Objects[0].Get('name', '') = 'Updated list',
          'Screen replay must not restore stale playlist metadata');

    Relay('{"type":"clock.sync.ping","playerId":"phone","clientSendUs":987654321.5}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('hostReceiveUs', int64(0)) = TestClock);
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('clientSendUs', double(0)) = 987654321.5);
    Game('{"type":"song.select.state","currentSong":{"audioPath":"private.wav","title":"Test"},"results":[{"txtPath":"private.txt"}],"library":[{"audioPath":"other.wav"}],"playlistItems":[{"songId":4,"title":"Playlist song","audioPath":"private.wav"}]}');
    Assert(Pos('private', Probe.Sent.Items[Probe.Sent.Count-1].AsJSON) = 0);
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Find('library') = nil);
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Arrays['playlistItems'].Count = 1,
      'Sanitized current playlist items must reach clients');
    Assert(Adapter.Songs.Count = 1, 'Game library must feed generic song snapshot');
    Assert(Adapter.Songs.Id <> '', 'Song snapshot needs a stable content identity');
    Game('{"type":"song.select.state","selectedSongId":8}');
    Relay('{"type":"song.state.request"}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Arrays['playlistItems'].Count = 1,
      'Partial selection updates must preserve full cached metadata for reconnect');

    Relay('{"type":"control.command","playerId":"phone","commandId":42,"command":"song.list","args":{"offset":0,"limit":10}}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('accepted', false));
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Objects['data'].Arrays['songs'].Count = 1);

    Game('{"type":"song.started","songSeq":1,"mediaStartUs":2000000}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('hostSongStartUs', int64(0)) = TestClock - 2000000);
    Game('{"type":"song.lyrics","songSeq":1,"lines":[]}');
    Game('{"type":"song.position","songSeq":1,"mediaStartUs":3000000,"hostStateUs":120000000,"scoringSongTimeUs":2980000}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('hostStateUs', int64(0)) = 120000000,
      'I/O processing must preserve the game-thread clock capture');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('hostSongStartUs', int64(0)) = 117000000);
    Game('{"type":"song.ended","songSeq":1}');
    Before := Probe.Sent.Count;
    Relay('{"type":"song.state.request"}');
    for I := Before to Probe.Sent.Count - 1 do
    begin
      Assert(TJSONObject(Probe.Sent.Items[I]).Get('type', '') <> 'song.started', 'Ended audio must not restart');
      Assert(TJSONObject(Probe.Sent.Items[I]).Get('type', '') <> 'song.lyrics', 'Ended lyrics must not replay');
    end;
    Before := Probe.Received.Count;
    Relay('{"type":"remote.players.snapshot","players":[{"playerId":"phone","name":"Daniel","slot":2,"role":"controller"}]}');
    Assert(Probe.Received.Count = Before + 1, 'Snapshot should be delivered once');
    Relay('{"type":"player.left","playerId":"phone"}');
    Relay('{"type":"song.state.request"}');
    for I := 0 to Probe.Sent.Count - 1 do
      Assert(TJSONObject(Probe.Sent.Items[I]).Get('protocol', 0) = 1);
    MediaPath := GetTempFileName;
    try
      FileStream := TFileStream.Create(MediaPath, fmCreate);
      Payload := 'abcdefghij';
      try FileStream.WriteBuffer(Payload[1], Length(Payload)); finally FileStream.Free; end;
      Snapshot := TJSONObject.Create(['type', 'song.library']);
      Snapshot.Add('library', TJSONArray.Create);
      Snapshot.Arrays['library'].Add(TJSONObject.Create(['songId', 7, 'audioPath', MediaPath]));
      try Assert(Adapter.FromGame(Snapshot)); finally Snapshot.Free; end;
      Relay('{"type":"song.preview.request","requestId":"media","songId":7,"purpose":"song-preview","rangeStart":2,"rangeEnd":5}');
      Adapter.TickMedia;
      Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('statusCode', 0) = 206);
      Adapter.TickMedia;
      Assert(DecodeStringBase64(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('data', '')) = 'cdef');
      Adapter.TickMedia;
      Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('type', '') = 'song.preview.end');
      Relay('{"type":"song.preview.request","requestId":"cancelled","songId":7,"purpose":"song-preview"}');
      Relay('{"type":"song.preview.cancel","requestId":"cancelled"}');
      Before := Probe.Sent.Count;
      Adapter.TickMedia;
      Assert(Probe.Sent.Count = Before, 'Cancelled media must not emit another message');
    finally DeleteFile(MediaPath); end;
    Game('{"type":"continuous.state","active":true}');
    Relay('{"type":"bridge.disconnected"}');
    Before := Probe.Sent.Count;
    Game('{"type":"game.state","state":"results","songSeq":1}');
    Assert(Probe.Sent.Count = Before);
    Relay('{"type":"room.resumed","roomId":"room","displayCode":"TEST","hostToken":"private"}');
    Assert(Probe.Sent.Count > Before);
    Assert(TJSONObject(Probe.Sent.Items[Before+1]).Get('type', '') = 'continuous.state');
    Assert(TJSONObject(Probe.Sent.Items[Before+1]).Get('active', false),
      'Reconnect must replay actual continuous activity before API readiness');
    Game('{"type":"continuous.state","active":false,"reason":"exhausted"}');
    Before := Probe.Sent.Count;
    Snapshot := nil;
    Relay('{"type":"song.state.request"}');
    Assert(not TJSONObject(Probe.Sent.Items[Before+1]).Get('active', true),
      'A stopped session must not replay an old active snapshot');
    Relay('{"type":"player.joined","playerId":"original","name":"Original singer","slot":2}');
    Game('{"type":"song.library","library":[{"songId":7,"catalogKey":"stable-file","title":"Fixture"}]}');
    Game('{"type":"continuous.state","active":true}');
    Game('{"type":"song.started","songSeq":31,"songId":7}');
    Relay('{"type":"bridge.disconnected"}');
    Relay('{"type":"player.left","playerId":"original"}');
    Relay('{"type":"player.joined","playerId":"replacement","name":"Other singer","slot":2}');
    Relay('{"type":"player.joined","playerId":"late","name":"Late singer","slot":3}');
    Game('{"type":"game.state","state":"singing","songSeq":31,"players":[{"playerId":"replacement","name":"Other singer","slot":2},{"playerId":"late","name":"Late singer","slot":3}]}');
    Relay('{"type":"player.left","playerId":"late"}');
    Game('{"type":"ack","commandId":99,"accepted":true}');
    Game('{"type":"p2p.ice","playerId":"original"}');
    Game('{"type":"score.snapshot","songSeq":31,"players":[{"slot":2,"scoreTotal":9000}]}');
    Game('{"type":"song.ended","songSeq":31,"players":[{"slot":2,"scoreTotal":9000},{"slot":3,"scoreTotal":4000}]}');
    Game('{"type":"continuous.state","active":false,"reason":"exhausted"}');
    Before := Probe.Sent.Count;
    Relay('{"type":"room.resumed","roomId":"room","displayCode":"TEST"}');
    for I := Before to Probe.Sent.Count - 1 do
      if TJSONObject(Probe.Sent.Items[I]).Get('type', '') = 'song.results' then
      begin
        Snapshot := TJSONObject(Probe.Sent.Items[I]);
        Assert(Snapshot.Arrays['rounds'].Count = 1);
        Assert(Snapshot.Arrays['rounds'].Objects[0].Get('catalogKey', '') = 'stable-file');
        Assert(Snapshot.Arrays['rounds'].Objects[0].Arrays['participants'].Objects[0].Get('playerId', '') = 'original',
          'Results retain the singer at song start, not the replacement in the slot');
          Assert(Snapshot.Arrays['rounds'].Objects[0].Arrays['participants'].Count = 2);
          Assert(Snapshot.Arrays['rounds'].Objects[0].Arrays['participants'].Objects[1].Get('playerId', '') = 'late',
            'Results retain newly admitted singers after they leave');
        Assert(Snapshot.Arrays['rounds'].Objects[0].Arrays['players'].Objects[0].Get('scoreTotal', 0) = 9000);
          Assert(Snapshot.Arrays['rounds'].Objects[0].Arrays['players'].Objects[1].Get('slot', 0) = 3);
          Assert(Snapshot.Arrays['rounds'].Objects[0].Arrays['players'].Objects[1].Get('scoreTotal', 0) = 4000);
      end;
    Assert(Assigned(Snapshot), 'Reconnect must contain the result journal');
    Before := Probe.Sent.Count;
    Game('{"type":"input.state","inputs":[],"playerColors":["#123456","#ABCDEF"]}');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Get('type', '') = 'api.state');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Arrays['playerColors'].Strings[1] = '#ABCDEF');
    Before := Probe.Sent.Count;
    Game('{"type":"input.state","inputs":[],"playerColors":["#123456","#ABCDEF"]}');
    Assert(Probe.Sent.Count = Before + 1, 'Unchanged colors must not republish API metadata');
    Before := Probe.Sent.Count;
    Game('{"type":"song.library","library":[]}');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Get('type', '') = 'api.state');
    Assert(TJSONObject(Probe.Sent.Items[Before]).Arrays['playerColors'].Strings[0] = '#123456',
      'Catalog refresh must retain the game color palette');
  finally Adapter.Free; Probe.Free; end;
  WriteLn('Native relay protocol: profile/slot merge, controls, clocks, state authority, privacy and ended-song replay passed');
end.
