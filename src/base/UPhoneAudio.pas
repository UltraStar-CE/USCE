{ Optional in-process phone PCM receiver. No web server or Node runtime. }
unit UPhoneAudio;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses SysUtils, Dynlibs, UAudioCalibrationSessions;

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
    FContexts: array[0..11] of pointer;
    FSignalLock: TRTLCriticalSection;
    FError: string;
    FCalibration: TAudioCalibrationSessions;
    FCreate: TPaCreate;
    FDestroy: TPaDestroy;
    FPoll: TPaPoll;
    FStatus: TPaStatus;
    FVersion: TPaVersion;
    FSignal: TPaSignal;
    FEvent: TPaStatus;
    function GetEnabled: boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Start(const Url, Ice: UTF8String; const LibraryPath: string = ''): boolean;
    procedure Stop;
    function Poll(Samples: pointer; Capacity: integer; PlayerIndex: integer = 0): integer;
    function Status(PlayerIndex: integer = 0): UTF8String;
    procedure Signal(const Json: UTF8String);
    property Enabled: boolean read GetEnabled;
    property LastError: string read FError;
    property Calibration: TAudioCalibrationSessions read FCalibration;
  end;

function PhoneAudio: TPhoneAudio;

implementation

uses URemoteBridgeIPC, fpjson, jsonparser;

var Instance: TPhoneAudio;

function PhoneAudio: TPhoneAudio;
begin
  if Instance = nil then Instance := TPhoneAudio.Create;
  Result := Instance;
end;

function TPhoneAudio.GetEnabled: boolean;
begin
  Result := FContexts[0] <> nil;
end;

constructor TPhoneAudio.Create;
begin
  inherited;
  InitCriticalSection(FSignalLock);
  FCalibration := TAudioCalibrationSessions.Create;
end;

function TPhoneAudio.Start(const Url, Ice: UTF8String; const LibraryPath: string): boolean;
var Path: string;
    RelayUrl, IceServer: UTF8String;
    I, Last: integer;
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
      Last := 0;
      if RelayUrl = 'ipc://' then Last := High(FContexts);
      for I := 0 to Last do
      begin
        FContexts[I] := FCreate(PAnsiChar(RelayUrl), PAnsiChar(IceServer));
        if FContexts[I] = nil then
        begin
          FError := 'Native phone audio receiver could not start';
          Stop;
          Break;
        end;
      end;
    end;
  end;
  Result := FContexts[0] <> nil;
  if not Result then Stop;
end;

procedure TPhoneAudio.Stop;
var I: integer;
begin
  EnterCriticalSection(FSignalLock);
  try
  for I := Low(FContexts) to High(FContexts) do
  begin
    if FContexts[I] <> nil then FDestroy(FContexts[I]);
    FContexts[I] := nil;
  end;
  if FLibrary <> NilHandle then UnloadLibrary(FLibrary);
  FLibrary := NilHandle;
  finally LeaveCriticalSection(FSignalLock); end;
end;

destructor TPhoneAudio.Destroy;
begin
  Stop;
  FCalibration.Free;
  DoneCriticalSection(FSignalLock);
  inherited;
end;

function TPhoneAudio.Poll(Samples: pointer; Capacity: integer; PlayerIndex: integer): integer;
var Buffer: array[0..131071] of AnsiChar;
    I, Count: integer;
begin
  Result := 0;
  if Enabled and (PlayerIndex >= 0) and (PlayerIndex <= High(FContexts)) and
    (FContexts[PlayerIndex] <> nil) then
  begin
    Result := FPoll(FContexts[PlayerIndex], Samples, Capacity);
    for I := 1 to 128 do
    begin
      Count := FEvent(FContexts[PlayerIndex], @Buffer[0], Length(Buffer));
      if Count <= 0 then Break;
      RemoteBridgeIPC.SendJsonMessage(string(PAnsiChar(@Buffer[0])));
    end;
  end;
end;

procedure TPhoneAudio.Signal(const Json: UTF8String);
var Data: TJSONData; Obj: TJSONObject; Entries: TJSONArray;
    I, J, Slot, OriginalSlot: integer; Kind, Text: UTF8String;
begin
  EnterCriticalSection(FSignalLock);
  try
  if not Enabled then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(string(Json));
      if Data.JSONType <> jtObject then Exit;
      Obj := TJSONObject(Data);
      Kind := UTF8String(Obj.Get('type', ''));
      OriginalSlot := Obj.Get('slot', 0);
      for I := Low(FContexts) to High(FContexts) do
      begin
        if FContexts[I] = nil then Continue;
        // These fields originate in the authenticated relay's roster, never in PCM.
        if (Kind = 'audio.pcm') or (Copy(Kind, 1, 4) = 'p2p.') then
          if OriginalSlot <> I + 1 then Continue;
        if Obj.IndexOfName('slot') >= 0 then
        begin
          Slot := 0;
          if OriginalSlot = I + 1 then Slot := 1;
          Obj.Integers['slot'] := Slot;
        end;
        if Kind = 'remote.players.snapshot' then
        begin
          // Reparse per lane so each snapshot preserves its original slot numbers.
          Data.Free;
          Data := nil;
          Data := GetJSON(string(Json));
          Obj := TJSONObject(Data);
          Entries := Obj.Arrays['players'];
          for J := 0 to Entries.Count - 1 do
            if Entries.Items[J].JSONType = jtObject then
            begin
              Slot := TJSONObject(Entries.Items[J]).Get('slot', 0);
              if Slot = I + 1 then Slot := 1 else Slot := 0;
              TJSONObject(Entries.Items[J]).Integers['slot'] := Slot;
            end;
        end;
        Text := UTF8String(Obj.AsJSON);
        FSignal(FContexts[I], PAnsiChar(Text));
      end;
    except
      // Malformed signaling must not terminate the bridge reader thread.
    end;
  finally
    Data.Free;
  end;
  finally LeaveCriticalSection(FSignalLock); end;
end;

function TPhoneAudio.Status(PlayerIndex: integer): UTF8String;
var Buffer: array[0..2047] of AnsiChar;
begin
  Result := '';
  if Enabled and (PlayerIndex >= 0) and (PlayerIndex <= High(FContexts)) and
    (FContexts[PlayerIndex] <> nil) and
    (FStatus(FContexts[PlayerIndex], @Buffer[0], Length(Buffer)) >= 0) then
    Result := PAnsiChar(@Buffer[0]);
end;

finalization
  FreeAndNil(Instance);
end.
