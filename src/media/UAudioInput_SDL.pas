// UltraStar Community Edition - Karaoke Game
// SPDX-License-Identifier: GPL-2.0-or-later

unit UAudioInput_SDL;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I ../switches.inc}

uses
  Classes,
  SysUtils,
  UMusic;

procedure SDLCaptureDeviceAdded;
procedure SDLCaptureDeviceRemoved(DeviceID: cardinal);

implementation

uses
  sdl2,
  ctypes,
  math,
  UIni,
  ULog,
  UPulseCaptureIdentity,
  UMediaCore_SDL,
  {$IFDEF LINUX}
  UUSBCaptureIdentity,
  Process, fpjson, jsonparser,
  {$ENDIF}
  URecord;

type
  TAudioInput_SDL = class(TAudioInputBase)
    private
      Initialized: boolean;
      function EnumDevices(): boolean;
    public
      function GetName: string; override;
      function InitializeRecord(ScanMode: TAudioInputScanMode): boolean; override;
      function FinalizeRecord: boolean; override;
  end;

  TSDLInputDevice = class(TAudioInputDevice)
    private
      DevID:   TSDL_AudioDeviceID;
      SDLName, Identity: UTF8String;
      USBModel, USBInstance: UTF8String;
      OpenedName, OpenedIdentity, OpenedInstance: UTF8String;
      CaptureWanted, Removed, RetryPending: boolean;
      NextReconnectAttempt: QWord;
      function CaptureActive: boolean;
      function CaptureAssigned: boolean;
      function OpenCapture(Reconnect: boolean = false): boolean;
      procedure CheckCapture(Now: System.QWord); override;
    public
      function Start(): boolean; override;
      function Stop():  boolean; override;

      function GetVolume(): single;        override;
      procedure SetVolume(Volume: single); override;
  end;

procedure MicrophoneCallback(inputDevice: TSDLInputDevice; input: pointer; len: cint); cdecl;
begin
  AudioInputProcessor.HandleMicrophoneData(input, len, inputDevice);
end;

// SDL may append a changing numeric suffix to identical capture devices.
function CaptureNameFamily(const Name: UTF8String): UTF8String;
var I: integer;
begin
  Result := Name;
  I := Length(Name);
  if (I < 5) or (Name[I] <> ')') then Exit;
  Dec(I);
  if not (Name[I] in ['0'..'9']) then Exit;
  while (I > 0) and (Name[I] in ['0'..'9']) do Dec(I);
  if (I > 2) and (Name[I] = '(') and (Name[I-1] = ' ') then
    SetLength(Result, I-2);
end;

{$IFDEF LINUX}
function PipeWireCaptureCard(const Tag: UTF8String): integer;
var
  Output, Target: string;
  Nodes, Links, Entry, Props, Value: TJSONData;
  StreamNode, SourceNode, FromNode, I: integer;
begin
  Result := -1;
  if not FileExists('/usr/bin/pw-dump') or not FileExists('/usr/bin/timeout') then Exit;
  try
    if not RunCommand('/usr/bin/timeout', ['--kill-after=1', '1', '/usr/bin/pw-dump', 'Node'], Output) then Exit;
    Nodes := GetJSON(Output);
    try
      if Nodes.JSONType <> jtArray then Exit;
      StreamNode := -1;
      SourceNode := -1;
      for I := 0 to Nodes.Count - 1 do
      begin
        Entry := Nodes.Items[I];
        Props := Entry.FindPath('info.props');
        if not (Props is TJSONObject) then Continue;
        Value := TJSONObject(Props).Find('node.name');
        if (Value = nil) or (Value.AsString <> Tag) then Continue;
        if StreamNode >= 0 then Exit;
        // These properties are set for explicit targets by the bundled SDL.
        Value := TJSONObject(Props).Find('node.dont-move');
        if (Value = nil) or not SameText(Value.AsString, 'true') then Exit;
        Value := TJSONObject(Props).Find('node.dont-fallback');
        if (Value = nil) or not SameText(Value.AsString, 'true') then Exit;
        Value := TJSONObject(Props).Find('node.dont-reconnect');
        if (Value = nil) or not SameText(Value.AsString, 'true') then Exit;
        Value := TJSONObject(Props).Find('target.object');
        if (Value = nil) or (Value.AsString = '') then Exit;
        Target := Value.AsString;
        StreamNode := TJSONObject(Entry).Get('id', -1);
      end;
      if StreamNode < 0 then Exit;
      if not RunCommand('/usr/bin/timeout', ['--kill-after=1', '1', '/usr/bin/pw-dump', 'Link'], Output) then Exit;
      Links := GetJSON(Output);
      try
        if Links.JSONType <> jtArray then Exit;
        for I := 0 to Links.Count - 1 do
        begin
          Entry := Links.Items[I];
          Value := Entry.FindPath('info.input-node-id');
          if (Value = nil) or (Value.AsInteger <> StreamNode) then Continue;
          Value := Entry.FindPath('info.output-node-id');
          if Value = nil then Exit;
          FromNode := Value.AsInteger;
          if (SourceNode >= 0) and (SourceNode <> FromNode) then Exit;
          SourceNode := FromNode;
        end;
      finally
        Links.Free;
      end;
      if SourceNode < 0 then Exit;
      for I := 0 to Nodes.Count - 1 do
      begin
        Entry := Nodes.Items[I];
        if TJSONObject(Entry).Get('id', -1) = SourceNode then
        begin
          Props := Entry.FindPath('info.props');
          if Props is TJSONObject then
          begin
            Value := TJSONObject(Props).Find('node.name');
            if (Value = nil) or (Value.AsString <> Target) then Exit;
            Value := TJSONObject(Props).Find('api.alsa.pcm.card');
            if Value <> nil then Result := Value.AsInteger;
          end;
          Exit;
        end;
      end;
    finally
      Nodes.Free;
    end;
  except
    on E: Exception do Result := -1;
  end;
end;
{$ENDIF}

var CaptureTagCounter: cardinal;

function OpenIdentifiedCapture(Name: PChar; var Spec: TSDL_AudioSpec;
  out Key, Serial, Model, Instance: UTF8String;
  AllowedChanges: integer = 0): TSDL_AudioDeviceID;
const StreamHint = 'SDL_AUDIO_DEVICE_STREAM_NAME';
var
  Tag, Previous, Driver: UTF8String;
  {$IFDEF LINUX}
  Card: integer;
  {$ENDIF}
  Tagged: boolean;
begin
  Key := '';
  Serial := '';
  Model := '';
  Instance := '';
  Tagged := false;
  Driver := SDL_GetCurrentAudioDriver;
  if (Driver = 'pulseaudio') or (Driver = 'alsa') or (Driver = 'pipewire') then
  begin
    Previous := SDL_GetHint(StreamHint);
    Inc(CaptureTagCounter);
    Tag := 'USCE-' + IntToHex(PtrUInt(@CaptureTagCounter), SizeOf(Pointer)*2) +
      '-' + IntToHex(GetTickCount64, 16) + '-' + IntToHex(CaptureTagCounter, 8);
    Tagged := SDL_SetHint(StreamHint, PChar(Tag));
  end;
  try
    // SDL opens paused so the caller can compare identities before unpausing.
    Result := SDL_OpenAudioDevice(Name, 1, @Spec, @Spec, AllowedChanges);
  finally
    if Tagged then SDL_SetHint(StreamHint, PChar(Previous));
  end;
  if (Result = 0) or not Tagged then Exit;
  if Driver = 'pulseaudio' then GetPulseCaptureIdentity(Tag, Key, Serial, Model, Instance);
  {$IFDEF LINUX}
  if Driver = 'alsa' then
  begin
    // The bundled SDL reports the card from snd_pcm_info on this paused stream.
    if TryStrToInt(SDL_GetHint(PChar(Tag)), Card) then
      Key := USBCaptureIdentity(Card, Serial, Model, Instance);
    SDL_SetHint(PChar(Tag), '');
  end;
  if Driver = 'pipewire' then
    Key := USBCaptureIdentity(PipeWireCaptureCard(Tag), Serial, Model, Instance);
  {$ENDIF}
end;

function TSDLInputDevice.Start(): boolean;
begin
  CaptureWanted := true;
  RetryPending := false;
  Result := OpenCapture;
  if not Result then
    Log.LogError('Could not open input device "' + Name + '": ' + SDL_GetError, 'SDL');
end;

function TSDLInputDevice.CaptureActive: boolean;
begin
  Result := (DevID <> 0) and not Removed and (SDL_GetAudioDeviceStatus(DevID) <> SDL_AUDIO_STOPPED);
end;

function TSDLInputDevice.CaptureAssigned: boolean;
var
  Player: integer;
begin
  if CaptureWanted then Exit(true);
  if (CfgIndex >= 0) and (CfgIndex < Length(Ini.InputDeviceConfig)) then
    for Player in Ini.InputDeviceConfig[CfgIndex].ChannelToPlayerMap do
      if Player <> CHANNEL_OFF then Exit(true);
  Result := false;
end;

function TSDLInputDevice.OpenCapture(Reconnect: boolean): boolean;
type
  TMatch = (NoMatch, SameFamily, SameName, SameModel, SamePort, SameAttachment, SameIdentity);
var
  Spec, RequestedSpec, CandidateSpec: TSDL_AudioSpec;
  CandidateID: TSDL_AudioDeviceID;
  I, CaptureLatencyMs: integer;
  Candidate, Family, Key, Serial, Model, Instance: UTF8String;
  Match, BestMatch, ExactMatch: TMatch;
  {$IFDEF LINUX}
  Peers: array of UTF8String;
  Device: TAudioInputDevice;
  Other: TSDLInputDevice;
  {$ENDIF}

  function USBPort(const Attachment: UTF8String): UTF8String;
  begin
    Result := Copy(Attachment, 1, LastDelimiter(':', Attachment) - 1);
  end;

  function SharesCaptureHardware(Other: TSDLInputDevice): boolean;
  begin
    Result := ((Identity <> '') and (Identity = Other.Identity)) or
      ((USBInstance <> '') and (Other.USBInstance <> '') and
       (USBPort(USBInstance) = USBPort(Other.USBInstance)));
  end;

  function SourceClaimed(const CandidateName, CandidateKey, CandidateInstance: UTF8String): boolean;
  var
    Device: TAudioInputDevice;
    Other: TSDLInputDevice;
    SharedHardware, SeparateEndpoint: boolean;
  begin
    for Device in AudioInputProcessor.DeviceList do
      if (Device is TSDLInputDevice) and (Device <> Self) then
      begin
        Other := TSDLInputDevice(Device);
        // A card can expose several independently assigned capture endpoints.
        SharedHardware := (SDLName <> Other.SDLName) and SharesCaptureHardware(Other);
        SeparateEndpoint := SharedHardware and (CandidateName = SDLName);
        if Other.CaptureActive then
        begin
          if not SeparateEndpoint or (Other.OpenedName <> Other.SDLName) then
          begin
            if (CandidateKey <> '') and (CandidateKey = Other.OpenedIdentity) then Exit(true);
            if (CandidateInstance <> '') and (CandidateInstance = Other.OpenedInstance) then Exit(true);
          end;
          if (CandidateName = Other.OpenedName) and
             ((CandidateKey = '') or (Other.OpenedIdentity = '')) and
             ((CandidateInstance = '') or (Other.OpenedInstance = '')) then Exit(true);
        end;
        if Other.CaptureAssigned then
        begin
          if SharedHardware and (CandidateName = Other.SDLName) then Exit(true);
          // Leave a verified match for its assigned slot even if it is waiting.
          if (CandidateKey <> '') and (CandidateKey <> Identity) and (CandidateKey = Other.Identity) then Exit(true);
          if (CandidateInstance <> '') and (CandidateInstance <> USBInstance) and
             (CandidateInstance = Other.USBInstance) and not SeparateEndpoint then Exit(true);
        end;
      end;
    Result := false;
  end;
begin
  Result := false;

  if DevID = 0 then
  begin
    FillChar(spec, SizeOf(spec), 0);
    with spec do
    begin
      freq := Round(AudioFormat.SampleRate);
      format := AUDIO_S16SYS;
      channels := AudioFormat.Channels;
      callback := @MicrophoneCallback;
      userdata := pointer(Self);

      CaptureLatencyMs := Ini.InputDeviceConfig[CfgIndex].Latency;
      if CaptureLatencyMs <= 0 then CaptureLatencyMs := 20;
      samples := 1 shl Round(EnsureRange(Log2(freq / 1000 * CaptureLatencyMs), 0, 15));
    end;

    OpenedName := SDLName;
    OpenedIdentity := '';
    OpenedInstance := '';
    if SDLName = '' then
      DevID := SDL_OpenAudioDevice(nil, 1, @spec, @spec, 0)
    else if not Reconnect and (Identity = '') and (USBModel = '') and (USBInstance = '') then
    begin
      if not SourceClaimed(SDLName, '', '') then
        DevID := SDL_OpenAudioDevice(PChar(SDLName), 1, @spec, @spec, 0);
    end
    else
    begin
      {$IFDEF LINUX}
      if USBModel <> '' then
      begin
        // Wait for a free attachment before reopening named SDL endpoints.
        Peers := nil;
        for Device in AudioInputProcessor.DeviceList do
          if (Device is TSDLInputDevice) and (Device <> Self) then
          begin
            Other := TSDLInputDevice(Device);
            if (Other.OpenedInstance = '') or not Other.CaptureActive then Continue;
            if (SDLName <> Other.SDLName) and (Other.OpenedName = Other.SDLName) and
               SharesCaptureHardware(Other) then Continue;
            SetLength(Peers, Length(Peers) + 1);
            Peers[High(Peers)] := Other.OpenedInstance;
          end;
        if not USBModelAvailable(USBModel, Peers) then Exit;
      end;
      {$ENDIF}

      RequestedSpec := Spec;
      Family := CaptureNameFamily(SDLName);
      BestMatch := NoMatch;
      ExactMatch := SameName;
      if USBModel <> '' then ExactMatch := SameModel;
      if USBInstance <> '' then ExactMatch := SameAttachment;
      if Identity <> '' then ExactMatch := SameIdentity;
      for I := -1 to SDL_GetNumAudioDevices(1) - 1 do
      begin
        if I < 0 then Candidate := SDLName
        else
        begin
          Candidate := SDL_GetAudioDeviceName(I, 1);
          if (Candidate = SDLName) or (CaptureNameFamily(Candidate) <> Family) then Continue;
        end;
        CandidateSpec := RequestedSpec;
        CandidateID := OpenIdentifiedCapture(PChar(Candidate), CandidateSpec, Key, Serial, Model, Instance);
        if CandidateID = 0 then Continue;

        Match := SameFamily;
        if Candidate = SDLName then Match := SameName;
        if (Model <> '') and (Model = USBModel) then Match := SameModel;
        if (Instance <> '') and (USBPort(Instance) = USBPort(USBInstance)) then Match := SamePort;
        if (Instance <> '') and (Instance = USBInstance) then Match := SameAttachment;
        if (Key <> '') and (Key = Identity) then Match := SameIdentity;
        // Prefer the original name for equally strong matches, then a stable name order.
        if (Match < BestMatch) or
           ((Match = BestMatch) and (Candidate <> SDLName) and
            ((OpenedName = SDLName) or (CompareStr(Candidate, OpenedName) >= 0))) or
           ((USBModel <> '') and (Model <> '') and (Model <> USBModel)) or
           SourceClaimed(Candidate, Key, Instance) then
        begin
          SDL_CloseAudioDevice(CandidateID);
          Continue;
        end;
        if DevID <> 0 then SDL_CloseAudioDevice(DevID);
        DevID := CandidateID;
        Spec := CandidateSpec;
        BestMatch := Match;
        OpenedName := Candidate;
        OpenedIdentity := Key;
        OpenedInstance := Instance;
        if (Candidate = SDLName) and (Match >= ExactMatch) then Break;
      end;
    end;
    if DevID > 0 then
    begin
      Log.LogStatus('InputDevice "' + Name + '" opened: ' + SDLAudioSpecToStr(spec) +
        ', ' + IntToStr(spec.samples) + ' samples (' +
        IntToStr(Round(spec.samples * 1000 / spec.freq)) + ' ms) per callback', 'SDL');
      // Keep the original verified identity if a same-model substitute was needed.
      if (OpenedInstance <> '') and ((Identity = '') or (OpenedIdentity = Identity)) then
        USBInstance := OpenedInstance;
      Removed := false;
      SDL_PauseAudioDevice(DevID, 0);
    end;
  end;

  Result := (DevID > 0);
end;

function TSDLInputDevice.Stop(): boolean;
begin
  CaptureWanted := false;
  RetryPending := false;
  Removed := false;
  if DevID <> 0 then SDL_CloseAudioDevice(DevID);
  DevID := 0;
  Result := true;
end;

procedure TSDLInputDevice.CheckCapture(Now: System.QWord);
begin
  if not CaptureWanted then Exit;
  if DevID <> 0 then
  begin
    // A mute or a suspended PulseAudio source can still be attached.
    // Closing it here would wait for the capture thread to receive data.
    if CaptureActive then
    begin
      RetryPending := false;
      Exit;
    end;

    SDL_CloseAudioDevice(DevID);
    DevID := 0;
    Removed := false;
    ResetCaptureAnalysis;
    NextReconnectAttempt := 0;
    Log.LogStatus('SDL input "' + Name + '" disconnected. Waiting for a matching device.', 'SDL');
  end;
  if not RetryPending and (Now < NextReconnectAttempt) then Exit;
  RetryPending := false;
  NextReconnectAttempt := GetTickCount64 + 1500;
  if OpenCapture(true) then
    Log.LogStatus('SDL input device "' + Name + '" reopened', 'SDL');
end;


procedure SDLCaptureDeviceAdded;
var
  Device: TAudioInputDevice;
begin
  if not Assigned(AudioInputProcessor) then Exit;
  for Device in AudioInputProcessor.DeviceList do
    if Device is TSDLInputDevice then
      TSDLInputDevice(Device).RetryPending := true;
end;

procedure SDLCaptureDeviceRemoved(DeviceID: cardinal);
var
  Device: TAudioInputDevice;
begin
  if (DeviceID = 0) or not Assigned(AudioInputProcessor) then Exit;
  for Device in AudioInputProcessor.DeviceList do
    if (Device is TSDLInputDevice) and (TSDLInputDevice(Device).DevID = DeviceID) then
      TSDLInputDevice(Device).Removed := true;
end;

function TSDLInputDevice.GetVolume(): single;
begin
  Result := 0;
end;

procedure TSDLInputDevice.SetVolume(Volume: single);
begin
end;

function TAudioInput_SDL.GetName: String;
begin
  Result := 'SDL';
  if SDL_WasInit(SDL_INIT_AUDIO) <> 0 then
    Result := Result + ' (' + SDL_GetCurrentAudioDriver + ')';
end;

function TAudioInput_SDL.EnumDevices(): boolean;
var
  i:            integer;
  deviceIndex:  integer;
  maxDevices:   integer;
  name:         PChar;
  device:       TSDLInputDevice;
  spec:         TSDL_AudioSpec;
  dev:          TSDL_AudioDeviceID;
  deviceName:   UTF8String;
  SDLName, Identity, Serial, Model, Instance: UTF8String;
  Preferred: TSDL_AudioSpec;
begin
  Result := false;

  LogSDLAudioInfo(true);

  maxDevices := SDL_GetNumAudioDevices(1);
  if maxDevices < 1 then
    maxDevices := 1;

  // init array-size to max. input-devices count
  SetLength(AudioInputProcessor.DeviceList, maxDevices);

  deviceIndex := 0;
  for i := 0 to High(AudioInputProcessor.DeviceList) do
  begin
    name := SDL_GetAudioDeviceName(i, 1);
    if (name = nil) and (i > 0) then
      break;

    SDLName := name;
    deviceName := DEFAULT_SOURCE_NAME;
    if SDLName <> '' then deviceName := SDLName;
    deviceName := UnifyDeviceName(deviceName, i);
    if not ShouldProbeDevice(deviceName) then
      continue;

    FillChar(spec, SizeOf(spec), 0);
    with spec do
    begin
      freq := 44100;
      format := AUDIO_S16SYS;
      channels := 0; // override with SDL_AUDIO_CHANNELS
      samples := 0;
    end;

    Identity := '';
    Serial := '';
    Model := '';
    Instance := '';
    if (SDLName <> '') then
    begin
      if SDLGetAudioDeviceSpec(i, true, Preferred) then
      begin
        if GetEnvironmentVariable('SDL_AUDIO_CHANNELS') = '' then
          spec.channels := Min(Preferred.channels, 8);
        if Preferred.freq > 0 then spec.freq := Preferred.freq;
      end;
      dev := OpenIdentifiedCapture(PChar(SDLName), spec, Identity, Serial, Model, Instance,
        SDL_AUDIO_ALLOW_FREQUENCY_CHANGE or SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
      if (dev = 0) and ((spec.channels > 0) or (spec.freq <> 44100)) then
      begin
        // Keep working with the SDL defaults if this profile cannot be opened.
        spec.freq := 44100;
        spec.format := AUDIO_S16SYS;
        spec.channels := 0;
        spec.samples := 0;
        dev := OpenIdentifiedCapture(PChar(SDLName), spec, Identity, Serial, Model, Instance,
          SDL_AUDIO_ALLOW_FREQUENCY_CHANGE or SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
      end;
    end
    else
      dev := SDL_OpenAudioDevice(name, 1, @spec, @spec,
        SDL_AUDIO_ALLOW_FREQUENCY_CHANGE or SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
    if dev < 1 then
      continue;

    SDL_CloseAudioDevice(dev);

    device := TSDLInputDevice.Create();
    device.Name := deviceName;
    device.SDLName := SDLName;
    device.Identity := Identity;
    device.USBModel := Model;
    device.USBInstance := Instance;
    device.CaptureSerial := Serial;

    device.MicSource := -1;
    device.SourceRestore := -1;
    SetLength(device.Source, 1);
    device.Source[0].Name := DEFAULT_SOURCE_NAME;

    // create audio-format info and resize capture-buffer array
    device.AudioFormat := TAudioFormatInfo.Create(
        spec.channels,
        spec.freq,
        asfS16
    );
    SetLength(device.CaptureChannel, device.AudioFormat.Channels);

    Log.LogStatus('InputDevice "' + device.Name + '"@' +
        IntToStr(device.AudioFormat.Channels) + 'x' +
        FloatToStr(device.AudioFormat.SampleRate) + 'Hz ' +
        'defaults to ' + IntToStr(spec.samples) + ' samples buffer',
        'SDL');

    AudioInputProcessor.DeviceList[deviceIndex] := device;
    Inc(deviceIndex);
  end;

  // adjust size to actual input-device count
  SetLength(AudioInputProcessor.DeviceList, deviceIndex);
  Log.LogStatus('#Input-Devices: ' + IntToStr(deviceIndex), 'SDL');
  Result := (deviceIndex > 0) or (ScanMode = aimFast);
end;

function TAudioInput_SDL.InitializeRecord(ScanMode: TAudioInputScanMode): boolean;
begin
  Result := false;

  if SDL_InitSubSystem(SDL_INIT_AUDIO) = -1 then
    Exit;

  Initialized := true;
  PrepareDeviceScan(ScanMode);
  Result := EnumDevices();
end;

function TAudioInput_SDL.FinalizeRecord: boolean;
begin
  CaptureStop;
  if Initialized then
  begin
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    Initialized := false;
  end;
  Result := inherited FinalizeRecord();
end;

initialization
  MediaManager.add(TAudioInput_SDL.Create);

end.
