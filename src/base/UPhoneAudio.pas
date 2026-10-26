{ Optional in-process phone PCM receiver. No web server or Node runtime. }
unit UPhoneAudio;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses SysUtils, Dynlibs;

type
  TPaCreate = function(Url, Ice: PAnsiChar): pointer; cdecl;
  TPaDestroy = procedure(Context: pointer); cdecl;
  TPaPoll = function(Context: pointer; Samples: pointer; Capacity: longint): longint; cdecl;
  TPaStatus = function(Context: pointer; Buffer: PAnsiChar; Capacity: longint): longint; cdecl;
  TPaVersion = function: longint; cdecl;
  TPaSignal = function(Context: pointer; Json: PAnsiChar): longint; cdecl;
  TPhoneAudio = class
  private
    FLibrary: TLibHandle;
    FContext: pointer;
    FError: string;
    FCreate: TPaCreate;
    FDestroy: TPaDestroy;
    FPoll: TPaPoll;
    FStatus: TPaStatus;
    FVersion: TPaVersion;
    FSignal: TPaSignal;
    FEvent: TPaStatus;
    function GetEnabled: boolean;
  public
    destructor Destroy; override;
    function Start(const Url, Ice: UTF8String; const LibraryPath: string = ''): boolean;
    procedure Stop;
    function Poll(Samples: pointer; Capacity: integer): integer;
    function Status: UTF8String;
    procedure Signal(const Json: UTF8String);
    property Enabled: boolean read GetEnabled;
    property LastError: string read FError;
  end;

function PhoneAudio: TPhoneAudio;

implementation

uses URemoteBridgeIPC;

var Instance: TPhoneAudio;

function PhoneAudio: TPhoneAudio;
begin
  if Instance = nil then Instance := TPhoneAudio.Create;
  Result := Instance;
end;

function TPhoneAudio.GetEnabled: boolean;
begin
  Result := FContext <> nil;
end;

function TPhoneAudio.Start(const Url, Ice: UTF8String; const LibraryPath: string): boolean;
var Path: string;
    RelayUrl, IceServer: UTF8String;
begin
  Stop;
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
    FError := 'Cannot load native phone audio library: ' + Path
  else
  begin
    FVersion := TPaVersion(GetProcedureAddress(FLibrary, 'usce_pa_version'));
    FCreate := TPaCreate(GetProcedureAddress(FLibrary, 'usce_pa_create'));
    FDestroy := TPaDestroy(GetProcedureAddress(FLibrary, 'usce_pa_destroy'));
    FPoll := TPaPoll(GetProcedureAddress(FLibrary, 'usce_pa_poll'));
    FStatus := TPaStatus(GetProcedureAddress(FLibrary, 'usce_pa_status'));
    FSignal := TPaSignal(GetProcedureAddress(FLibrary, 'usce_pa_signal'));
    FEvent := TPaStatus(GetProcedureAddress(FLibrary, 'usce_pa_event'));
    if not (Assigned(FVersion) and Assigned(FCreate) and Assigned(FDestroy) and
      Assigned(FPoll) and Assigned(FStatus) and Assigned(FSignal) and Assigned(FEvent)) then
      FError := 'Native phone audio library has an incomplete ABI'
    else if FVersion() <> 1 then
      FError := 'Native phone audio library ABI version mismatch'
    else
    begin
      RelayUrl := Url;
      IceServer := Ice;
      if RelayUrl = '' then RelayUrl := 'wss://usdx.at/ws/host';
      if IceServer = '' then IceServer := 'stun:stun.l.google.com:19302';
      FContext := FCreate(PAnsiChar(RelayUrl), PAnsiChar(IceServer));
      if FContext = nil then FError := 'Native phone audio receiver could not start';
    end;
  end;
  Result := FContext <> nil;
  if not Result then Stop;
end;

procedure TPhoneAudio.Stop;
begin
  if FContext <> nil then FDestroy(FContext);
  FContext := nil;
  if FLibrary <> NilHandle then UnloadLibrary(FLibrary);
  FLibrary := NilHandle;
end;

destructor TPhoneAudio.Destroy;
begin
  Stop;
  inherited;
end;

function TPhoneAudio.Poll(Samples: pointer; Capacity: integer): integer;
var Buffer: array[0..131071] of AnsiChar;
    I, Count: integer;
begin
  Result := 0;
  if Enabled then
  begin
    Result := FPoll(FContext, Samples, Capacity);
    for I := 1 to 128 do
    begin
      Count := FEvent(FContext, @Buffer[0], Length(Buffer));
      if Count <= 0 then Break;
      RemoteBridgeIPC.SendJsonMessage(string(PAnsiChar(@Buffer[0])));
    end;
  end;
end;

procedure TPhoneAudio.Signal(const Json: UTF8String);
begin
  if Enabled then FSignal(FContext, PAnsiChar(Json));
end;

function TPhoneAudio.Status: UTF8String;
var Buffer: array[0..2047] of AnsiChar;
begin
  Result := '';
  if Enabled and (FStatus(FContext, @Buffer[0], Length(Buffer)) >= 0) then
    Result := PAnsiChar(@Buffer[0]);
end;

finalization
  FreeAndNil(Instance);
end.
