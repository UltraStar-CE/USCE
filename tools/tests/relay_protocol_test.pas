program relay_protocol_test;
{$MODE Delphi}{$H+}{$ASSERTIONS ON}
uses SysUtils, fpjson, jsonparser, URemoteRelayProtocol;
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
    Game('{"type":"game.state","state":"player_setup","songSeq":0}');
    Assert(Probe.Sent.Count = 0, 'Disconnected state must wait for registration');
    Relay('{"type":"room.created","roomId":"room","displayCode":"TEST","hostToken":"private"}');
    Assert(Probe.Last.Find('hostToken') = nil, 'Credentials must stay in session');
    Assert(TJSONObject(Probe.Sent.Items[0]).Get('state', '') = 'player_setup');
    Relay('{"type":"player.joined","playerId":"phone","name":"Daniel","slot":1,"difficulty":2,"avatarFile":"phone.jpg","role":"controller"}');
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
    Relay('{"type":"song.state.request"}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('state', '') = 'player_setup');
    Relay('{"type":"clock.sync.ping","playerId":"phone","clientSendUs":987654321.5}');
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('hostReceiveUs', int64(0)) = TestClock);
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Get('clientSendUs', double(0)) = 987654321.5);
    Game('{"type":"song.select.state","currentSong":{"audioPath":"private.wav","title":"Test"},"results":[{"txtPath":"private.txt"}],"library":[{"audioPath":"other.wav"}],"playlistItems":[]}');
    Assert(Pos('private', Probe.Sent.Items[Probe.Sent.Count-1].AsJSON) = 0);
    Assert(TJSONObject(Probe.Sent.Items[Probe.Sent.Count-1]).Find('library') = nil);
    Assert(Adapter.Songs.Count = 1, 'Game library must feed generic song snapshot');
    Assert(Adapter.Songs.Id <> '', 'Song snapshot needs a stable content identity');
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
    Relay('{"type":"bridge.disconnected"}');
    Before := Probe.Sent.Count;
    Game('{"type":"game.state","state":"results","songSeq":1}');
    Assert(Probe.Sent.Count = Before);
    Relay('{"type":"room.resumed","roomId":"room","displayCode":"TEST","hostToken":"private"}');
    Assert(Probe.Sent.Count > Before);
  finally Adapter.Free; Probe.Free; end;
  WriteLn('Native relay protocol: profile/slot merge, controls, clocks, state authority, privacy and ended-song replay passed');
end.
