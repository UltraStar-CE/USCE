{ Pascal-owned relay session. Call Tick from a dedicated I/O thread, never a
  native callback. Room credentials stay in memory and are not logged. }
unit URemoteRelaySession;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses SysUtils, fpjson, URemoteRelaySocket;

type
  TRelayMessageEvent = procedure(Message: TJSONObject) of object;
  TRemoteRelaySession = class
  private
    FSocket: TRemoteRelaySocket;
    FUrl, FLibraryPath, FGameVersion: string;
    FRoomId, FHostToken, FDisplayCode: UTF8String;
    FHelloSent, FRunning, FRegistered: boolean;
    FRetryAt, FHeartbeatAt, FOpenedAt: QWord;
    FOnMessage: TRelayMessageEvent;
    procedure Hello;
    procedure Handle(Message: TJSONObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const Url, LibraryPath, GameVersion: string);
    procedure Stop;
    procedure Reconnect;
    procedure Tick;
    // Caller retains ownership. Protocol is set here, never by individual users.
    function Send(Message: TJSONObject): boolean;
    property Registered: boolean read FRegistered;
    property DisplayCode: UTF8String read FDisplayCode;
    property OnMessage: TRelayMessageEvent read FOnMessage write FOnMessage;
  end;

function NormalizeRelayHostUrl(const Url: string): string;

implementation

uses jsonparser;

function NormalizeRelayHostUrl(const Url: string): string;
var Address, Scheme, Query: string;
    Start, I: integer;
begin
  Result := Trim(Url);
  Scheme := LowerCase(Copy(Result, 1, 8));
  if Scheme = 'https://' then begin Scheme := 'wss://'; Start := 9; end
  else if Copy(Scheme, 1, 7) = 'http://' then begin Scheme := 'ws://'; Start := 8; end
  else Exit;
  Address := Copy(Result, Start, MaxInt);
  I := Pos('#', Address);
  if I > 0 then Delete(Address, I, MaxInt);
  Query := '';
  I := Pos('?', Address);
  if I > 0 then begin Query := Copy(Address, I, MaxInt); Delete(Address, I, MaxInt); end;
  I := Pos('/', Address);
  if I > 0 then Delete(Address, I, MaxInt);
  Result := Scheme + Address + '/ws/host' + Query;
end;

constructor TRemoteRelaySession.Create;
begin
  inherited;
  FSocket := TRemoteRelaySocket.Create;
end;

destructor TRemoteRelaySession.Destroy;
begin
  Stop;
  FSocket.Free;
  inherited;
end;

procedure TRemoteRelaySession.Start(const Url, LibraryPath, GameVersion: string);
begin
  Stop;
  FUrl := NormalizeRelayHostUrl(Url);
  FLibraryPath := LibraryPath;
  FGameVersion := GameVersion;
  FRunning := true;
  FRetryAt := 0;
end;

procedure TRemoteRelaySession.Stop;
begin
  FRunning := false;
  FRegistered := false;
  FHelloSent := false;
  FSocket.Close;
  FRoomId := '';
  FHostToken := '';
  FDisplayCode := '';
end;

procedure TRemoteRelaySession.Reconnect;
var Message: TJSONObject;
    WasRegistered: boolean;
begin
  WasRegistered := FRegistered;
  FRegistered := false;
  FHelloSent := false;
  FSocket.Close;
  FRetryAt := GetTickCount64 + 1000;
  // Preserve room credentials across transport interruptions. The service
  // creates a fresh room itself when the previous room has expired.
  if WasRegistered and Assigned(FOnMessage) then
  begin
    Message := TJSONObject.Create(['type', 'bridge.disconnected', 'protocol', 1]);
    try FOnMessage(Message); finally Message.Free; end;
  end;
end;

function TRemoteRelaySession.Send(Message: TJSONObject): boolean;
begin
  Message.Integers['protocol'] := 1;
  Result := FRunning and FSocket.Send(UTF8String(Message.AsJSON));
end;

procedure TRemoteRelaySession.Hello;
var Message: TJSONObject;
begin
  // Advertise only implemented capabilities. Catalog/Party will be added as
  // their handlers move into the game; this session alone is not feature parity.
  Message := TJSONObject.Create(['type', 'host.hello', 'gameVersion', FGameVersion,
    'bridgeVersion', 'usce-native', 'maxPlayers', 12]);
  try
    Message.Add('capabilities', TJSONArray.Create(['remoteControl', 'clockSync',
      'p2pDataChannel', 'rawPcmV1']));
    if FRoomId <> '' then
    begin
      Message.Add('roomId', string(FRoomId));
      Message.Add('hostToken', string(FHostToken));
    end;
    FHelloSent := Send(Message);
  finally Message.Free; end;
end;

procedure TRemoteRelaySession.Handle(Message: TJSONObject);
var Kind: string;
begin
  if Message.Get('protocol', 0) <> 1 then Exit;
  Kind := Message.Get('type', '');
  if (Kind = 'room.created') or (Kind = 'room.resumed') then
  begin
    FRoomId := UTF8String(Message.Get('roomId', ''));
    FHostToken := UTF8String(Message.Get('hostToken', ''));
    FDisplayCode := UTF8String(Message.Get('displayCode', ''));
    FRegistered := (FRoomId <> '') and (FHostToken <> '') and (FDisplayCode <> '');
  end;
  if Assigned(FOnMessage) then FOnMessage(Message);
end;

procedure TRemoteRelaySession.Tick;
var Now: QWord;
    Text: UTF8String;
    Data: TJSONData;
    Message: TJSONObject;
    I: integer;
begin
  if not FRunning then Exit;
  Now := GetTickCount64;
  if FSocket.State >= 2 then
  begin
    if FHelloSent then Reconnect;
    if Now < FRetryAt then Exit;
    FRetryAt := Now + 1000;
    if not FSocket.Open(UTF8String(FUrl), FLibraryPath) then Exit;
    FOpenedAt := Now;
  end;
  if not FRegistered and (Now - FOpenedAt > 10000) then
  begin
    Reconnect;
    Exit;
  end;
  if FSocket.State <> 1 then Exit;
  if not FHelloSent then Hello;
  for I := 1 to 128 do
  begin
    if not FSocket.Receive(Text) then Break;
    Data := nil;
    try
      try
        Data := GetJSON(string(Text));
        if Data.JSONType = jtObject then Handle(TJSONObject(Data));
      except
        // Malformed relay JSON cannot unwind the game I/O loop.
      end;
    finally Data.Free; end;
  end;
  if FRegistered and (Now >= FHeartbeatAt) then
  begin
    Message := TJSONObject.Create(['type', 'host.heartbeat']);
    try
      if Send(Message) then FHeartbeatAt := Now + 500;
    finally Message.Free; end;
  end;
end;

end.
