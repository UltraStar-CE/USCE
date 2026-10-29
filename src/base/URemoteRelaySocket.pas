{ In-process relay transport. Protocol and reconnect policy belong to Pascal;
  the existing native WebRTC library provides verified TLS and WebSocket I/O.
  One owner thread calls Open/Send/Receive/Close; native callbacks only enqueue. }
unit URemoteRelaySocket;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses SysUtils, Dynlibs;

type
  TRelayCreate = function(Url: PAnsiChar): pointer; cdecl;
  TRelayDestroy = procedure(Context: pointer); cdecl;
  TRelayState = function(Context: pointer): longint; cdecl;
  TRelaySend = function(Context: pointer; Text: PAnsiChar): longint; cdecl;
  TRelayReceive = function(Context: pointer; Text: PAnsiChar; Capacity: longint): longint; cdecl;
  TRemoteRelaySocket = class
  private
    FLibrary: TLibHandle;
    FContext: pointer;
    FCreate: TRelayCreate;
    FDestroy: TRelayDestroy;
    FState: TRelayState;
    FSend: TRelaySend;
    FReceive: TRelayReceive;
    FReadBuffer: UTF8String;
    FError: string;
  public
    destructor Destroy; override;
    function Open(const Url: UTF8String; const LibraryPath: string = ''): boolean;
    procedure Close;
    // State: 0 connecting, 1 open, 2 closed, 3 failed.
    function State: integer;
    // False means not accepted; the owner retains the message for retry.
    function Send(const Text: UTF8String): boolean;
    function Receive(out Text: UTF8String): boolean;
    property LastError: string read FError;
  end;

implementation

const MaxMessageBytes = 1024 * 1024;

function TRemoteRelaySocket.Open(const Url: UTF8String; const LibraryPath: string): boolean;
var Path: string;
begin
  Close;
  FError := '';
  Path := LibraryPath;
  if Path = '' then
  begin
    {$IFDEF MSWINDOWS}Path := 'usce-phone-audio.dll';{$ENDIF}
    {$IFDEF DARWIN}Path := 'libusce-phone-audio.dylib';{$ENDIF}
    {$IFDEF UNIX}{$IFNDEF DARWIN}Path := 'libusce-phone-audio.so';{$ENDIF}{$ENDIF}
    Path := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0)))) + Path;
  end;
  FLibrary := LoadLibrary(Path);
  if FLibrary = NilHandle then
    FError := 'Cannot load native relay transport: ' + Path
  else
  begin
    FCreate := TRelayCreate(GetProcedureAddress(FLibrary, 'usce_relay_create'));
    FDestroy := TRelayDestroy(GetProcedureAddress(FLibrary, 'usce_relay_destroy'));
    FState := TRelayState(GetProcedureAddress(FLibrary, 'usce_relay_state'));
    FSend := TRelaySend(GetProcedureAddress(FLibrary, 'usce_relay_send'));
    FReceive := TRelayReceive(GetProcedureAddress(FLibrary, 'usce_relay_receive'));
    if not (Assigned(FCreate) and Assigned(FDestroy) and Assigned(FState) and
      Assigned(FSend) and Assigned(FReceive)) then
      FError := 'Native relay transport has an incomplete ABI'
    else
    begin
      FContext := FCreate(PAnsiChar(Url));
      if FContext = nil then FError := 'Native relay connection could not start';
    end;
  end;
  Result := FContext <> nil;
  if not Result then Close;
end;

procedure TRemoteRelaySocket.Close;
begin
  if FContext <> nil then FDestroy(FContext);
  FContext := nil;
  if FLibrary <> NilHandle then UnloadLibrary(FLibrary);
  FLibrary := NilHandle;
  FReadBuffer := '';
end;

destructor TRemoteRelaySocket.Destroy;
begin
  Close;
  inherited;
end;

function TRemoteRelaySocket.State: integer;
begin
  Result := 3;
  if FContext <> nil then Result := FState(FContext);
end;

function TRemoteRelaySocket.Send(const Text: UTF8String): boolean;
begin
  Result := false;
  if (FContext = nil) or (Length(Text) = 0) or
    (Length(Text) > MaxMessageBytes) or (Pos(#0, Text) > 0) then Exit;
  Result := FSend(FContext, PAnsiChar(Text)) = 1;
end;

function TRemoteRelaySocket.Receive(out Text: UTF8String): boolean;
var Count: longint;
begin
  Result := false;
  Text := '';
  if FContext = nil then Exit;
  if FReadBuffer = '' then SetLength(FReadBuffer, MaxMessageBytes + 1);
  Count := FReceive(FContext, PAnsiChar(FReadBuffer), Length(FReadBuffer));
  if Count > 0 then
  begin
    SetString(Text, PAnsiChar(FReadBuffer), Count);
    Result := true;
  end
  else if Count < 0 then FError := 'Native relay receive failed';
end;

end.
