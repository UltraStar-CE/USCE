{ Relay/game message adaptation. Owned by the game I/O thread. No file access,
  gameplay calls or Node process. The game remains authoritative for its screen. }
unit URemoteRelayProtocol;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses SysUtils, fpjson, URemoteSongSnapshot;

type
  TRelayProtocolEvent = procedure(Message: TJSONObject) of object;
  TRelayProtocolSend = function(Message: TJSONObject): boolean of object;
  TRelayClock = function: int64;
  TRemoteRelayProtocol = class
  private
    FPlayers, FCache: TJSONObject;
    FSongs: TRemoteSongSnapshot;
    FRoomId: string;
    FOnGame: TRelayProtocolEvent;
    FOnSend: TRelayProtocolSend;
    FClock: TRelayClock;
    FReady: boolean;
    function NowUs: int64;
    function Send(Message: TJSONObject): boolean;
    procedure Deliver(Message: TJSONObject);
    procedure Cache(Message: TJSONObject);
    procedure Replay;
    procedure PlayerUpdate(Message: TJSONObject; Notify: boolean = true);
    function CopyPublic(Message: TJSONObject): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FromRelay(Message: TJSONObject);
    function FromGame(Message: TJSONObject): boolean;
    property Songs: TRemoteSongSnapshot read FSongs;
    property OnGame: TRelayProtocolEvent read FOnGame write FOnGame;
    property OnSend: TRelayProtocolSend read FOnSend write FOnSend;
    property Clock: TRelayClock read FClock write FClock;
  end;

implementation

function CloneObject(Message: TJSONObject): TJSONObject;
begin
  Result := TJSONObject(Message.Clone);
end;

procedure RemoveField(Message: TJSONObject; const Name: string);
var Index: integer;
begin
  Index := Message.IndexOfName(Name);
  if Index >= 0 then Message.Delete(Index);
end;

procedure StripLocalPaths(Data: TJSONData);
var I: integer;
    Obj: TJSONObject;
    Name: string;
begin
  if Data.JSONType = jtObject then
  begin
    Obj := TJSONObject(Data);
    for I := Obj.Count - 1 downto 0 do
    begin
      Name := Obj.Names[I];
      if (Name = 'audioPath') or (Name = 'coverPath') or (Name = 'txtPath') or
        (Name = 'filePath') or (Name = 'hostToken') then Obj.Delete(I)
      else StripLocalPaths(Obj.Items[I]);
    end;
  end
  else if Data.JSONType = jtArray then
    for I := 0 to Data.Count - 1 do StripLocalPaths(Data.Items[I]);
end;

constructor TRemoteRelayProtocol.Create;
begin
  inherited;
  FSongs := TRemoteSongSnapshot.Create;
  FPlayers := TJSONObject.Create;
  FCache := TJSONObject.Create;
end;

destructor TRemoteRelayProtocol.Destroy;
begin
  FSongs.Free;
  FPlayers.Free;
  FCache.Free;
  inherited;
end;

function TRemoteRelayProtocol.NowUs: int64;
begin
  if Assigned(FClock) then Result := FClock()
  else Result := int64(GetTickCount64) * 1000;
end;

function TRemoteRelayProtocol.Send(Message: TJSONObject): boolean;
begin
  Result := false;
  Message.Integers['protocol'] := 1;
  if FReady and Assigned(FOnSend) then Result := FOnSend(Message);
end;

procedure TRemoteRelayProtocol.Deliver(Message: TJSONObject);
begin
  if Assigned(FOnGame) then FOnGame(Message);
end;

procedure TRemoteRelayProtocol.Cache(Message: TJSONObject);
var Kind: string;
begin
  Kind := Message.Get('type', '');
  RemoveField(FCache, Kind);
  FCache.Add(Kind, Message.Clone);
end;

function TRemoteRelayProtocol.CopyPublic(Message: TJSONObject): TJSONObject;
var Players: TJSONArray;
    I: integer;
begin
  Result := CloneObject(Message);
  StripLocalPaths(Result);
  if Result.Get('type', '') = 'game.state' then
  begin
    // Relay roster updates never replace the game's screen or song sequence.
    RemoveField(Result, 'players');
    Players := TJSONArray.Create;
    for I := 0 to FPlayers.Count - 1 do Players.Add(FPlayers.Items[I].Clone);
    Result.Add('players', Players);
  end;
end;

procedure TRemoteRelayProtocol.Replay;
const Order: array[0..7] of string = ('input.state', 'game.state', 'screen.info',
  'playlist.state', 'song.select.state', 'song.clock', 'song.lyrics', 'score.sheet');
var I: integer;
    Data: TJSONData;
    Message: TJSONObject;
begin
  for I := Low(Order) to High(Order) do
  begin
    Data := FCache.Find(Order[I]);
    if (Data = nil) or (Data.JSONType <> jtObject) then Continue;
    Message := CopyPublic(TJSONObject(Data));
    try Send(Message); finally Message.Free; end;
  end;
end;

procedure TRemoteRelayProtocol.PlayerUpdate(Message: TJSONObject; Notify: boolean);
var Id: string;
    Profile, Existing: TJSONObject;
    Value: TJSONData;
    I: integer;
begin
  Id := Message.Get('playerId', '');
  if Id = '' then Exit;
  Value := FPlayers.Find(Id);
  if (Value <> nil) and (Value.JSONType = jtObject) then Existing := TJSONObject(Value)
  else Existing := nil;
  if Existing = nil then
  begin
    if FPlayers.Count >= 256 then Exit;
    Profile := TJSONObject.Create(['playerId', Id, 'slot', 0, 'connected', true]);
    FPlayers.Add(Id, Profile);
  end
  else Profile := Existing;
  if (Message.Get('type', '') = 'player.joined') or
    (Message.Get('type', '') = 'player.assigned') then Profile.Booleans['connected'] := true;
  for I := 0 to Message.Count - 1 do
    if (Message.Names[I] <> 'type') and (Message.Names[I] <> 'hostToken') then
    begin
      RemoveField(Profile, Message.Names[I]);
      Profile.Add(Message.Names[I], Message.Items[I].Clone);
    end;
  Profile.Strings['type'] := 'player.assigned';
  if Notify then Deliver(Profile);
end;

procedure TRemoteRelayProtocol.FromRelay(Message: TJSONObject);
var Kind, Id: string;
    Reply: TJSONObject;
    Data: TJSONData;
    Players: TJSONArray;
    I: integer;
begin
  Kind := Message.Get('type', '');
  if (Kind = 'room.created') or (Kind = 'room.resumed') then
  begin
    FReady := true;
    if FRoomId <> Message.Get('roomId', '') then
    begin
      FPlayers.Clear;
      FRoomId := Message.Get('roomId', '');
      Reply := TJSONObject.Create(['type', 'remote.players.snapshot', 'protocol', 1]);
      Reply.Add('players', TJSONArray.Create);
      try Deliver(Reply); finally Reply.Free; end;
    end;
    Reply := CopyPublic(Message);
    try Deliver(Reply); finally Reply.Free; end;
    Replay;
    Exit;
  end;
  if Kind = 'bridge.disconnected' then
  begin
    FReady := false;
    Deliver(Message);
    Exit;
  end;
  if Kind = 'clock.sync.ping' then
  begin
    Reply := TJSONObject.Create(['type', 'clock.sync.pong',
      'playerId', Message.Get('playerId', ''), 'hostReceiveUs', NowUs]);
    try
      Data := Message.Find('clientSendUs');
      if Data <> nil then Reply.Add('clientSendUs', Data.Clone);
      Reply.Add('hostSendUs', NowUs);
      Send(Reply);
    finally Reply.Free; end;
    Exit;
  end;
  if Kind = 'remote.players.snapshot' then
  begin
    Data := Message.Find('players');
    if (Data = nil) or (Data.JSONType <> jtArray) then Exit;
    Players := TJSONArray(Data);
    FPlayers.Clear;
    for I := 0 to Players.Count - 1 do
      if Players.Items[I].JSONType = jtObject then
        PlayerUpdate(TJSONObject(Players.Items[I]), false);
    Deliver(Message);
    Exit;
  end;
  if (Kind = 'player.joined') or (Kind = 'player.assigned') or
    (Kind = 'player.profile.updated') or (Kind = 'player.renamed') then
  begin
    PlayerUpdate(Message);
    Exit;
  end;
  if Kind = 'player.left' then RemoveField(FPlayers, Message.Get('playerId', ''));
  if Kind = 'player.disconnected' then
  begin
    Data := FPlayers.Find(Message.Get('playerId', ''));
    if (Data <> nil) and (Data.JSONType = jtObject) then
      TJSONObject(Data).Booleans['connected'] := false;
  end;
  if (Kind = 'control.command') or (Kind = 'settings.update') then
  begin
    Reply := CloneObject(Message);
    try
      Id := Message.Get('playerId', '');
      Data := FPlayers.Find(Id);
      if (Data <> nil) and (Data.JSONType = jtObject) then
      begin
        Reply.Integers['slot'] := TJSONObject(Data).Get('slot', 0);
        Reply.Strings['role'] := TJSONObject(Data).Get('role', 'controller');
      end;
      Deliver(Reply);
    finally Reply.Free; end;
    Exit;
  end;
  if Kind = 'song.state.request' then
  begin
    Replay;
    Exit;
  end;
  // The service's roster state can lag the game. Never feed it back as a
  // gameplay screen or overwrite the authoritative cached game.state.
  if (Kind = 'game.state') or (Kind = 'ack') then Exit;
  Deliver(Message);
end;

function TRemoteRelayProtocol.FromGame(Message: TJSONObject): boolean;
var Kind: string;
    PublicMessage: TJSONObject;
    Media: int64;
    Previous, LibraryData: TJSONData;
begin
  Kind := Message.Get('type', '');
  if (Kind = 'bridge.ping') or (Kind = 'continuous.state') then Exit(true);
  if Kind = 'song.select.state' then
  begin
    LibraryData := Message.Find('library');
    if (LibraryData <> nil) and (LibraryData.JSONType = jtArray) then
      FSongs.Replace(TJSONArray(LibraryData));
  end;
  PublicMessage := CopyPublic(Message);
  try
    if Kind = 'game.state' then
    begin
      Previous := FCache.Find('game.state');
      if (Previous <> nil) and (Previous.JSONType = jtObject) and
        (TJSONObject(Previous).Get('state', '') <> Message.Get('state', '')) then
        RemoveField(FCache, 'screen.info');
    end;
    if Kind = 'song.started' then
    begin
      RemoveField(FCache, 'song.lyrics');
      RemoveField(FCache, 'score.sheet');
    end;
    if Kind = 'song.select.state' then
    begin
      // Catalog and preview transfer are separate handlers. Never upload a
      // game's full private library (or local paths) as live screen state.
      RemoveField(PublicMessage, 'library');
      RemoveField(PublicMessage, 'playlistItems');
      RemoveField(PublicMessage, 'audioPath');
      RemoveField(PublicMessage, 'coverPath');
      RemoveField(PublicMessage, 'txtPath');
      PublicMessage.Int64s['hostStateUs'] := PublicMessage.Get('hostStateUs', NowUs);
    end;
    if (Kind = 'song.started') or (Kind = 'song.resumed') or
      (Kind = 'song.paused') or (Kind = 'song.position') or (Kind = 'song.ended') then
    begin
      PublicMessage.Int64s['hostStateUs'] := PublicMessage.Get('hostStateUs', NowUs);
      Media := PublicMessage.Get('mediaStartUs', int64(0));
      if Media < 0 then Media := 0;
      PublicMessage.Int64s['hostSongStartUs'] := PublicMessage.Int64s['hostStateUs'] - Media;
      if Kind = 'song.ended' then
      begin
        RemoveField(FCache, 'song.clock');
        RemoveField(FCache, 'song.lyrics');
      end
      else
      begin
        RemoveField(FCache, 'song.clock');
        FCache.Add('song.clock', PublicMessage.Clone);
      end;
    end;
    if (Kind = 'audio.stop') then
    begin
      RemoveField(FCache, 'song.clock');
      RemoveField(FCache, 'song.lyrics');
    end;
    if (Kind = 'input.state') or (Kind = 'game.state') or (Kind = 'screen.info') or
      (Kind = 'playlist.state') or (Kind = 'song.select.state') or
      (Kind = 'song.lyrics') or (Kind = 'score.sheet') then Cache(PublicMessage);
    // State can wait in the cache while reconnecting. Command results and
    // signaling retain their position in the caller's bounded output queue.
    Result := Send(PublicMessage);
    if not FReady and (FCache.Find(Kind) <> nil) then Result := true;
  finally PublicMessage.Free; end;
end;

end.
