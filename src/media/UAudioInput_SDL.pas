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

procedure CheckSDLCaptureDevices;
procedure SDLCaptureDeviceRemoved(DeviceID: cardinal);

implementation

uses
  sdl2,
  ctypes,
  math,
  UIni,
  ULog,
  UPulseCaptureIdentity,
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
      UseName, NeedsReassignment: boolean;
      SDLName, Identity: UTF8String;
      CaptureWanted, Removed, RetriedSilence: boolean;
      LastSignal, NextRetry: QWord;
      function OpenCapture(Reconnect: boolean = false): boolean;
      procedure CheckCapture(Now: QWord);
    public
      function Start(): boolean; override;
      function Stop():  boolean; override;

      function GetVolume(): single;        override;
      procedure SetVolume(Volume: single); override;
  end;

procedure MicrophoneCallback(inputDevice: TSDLInputDevice; input: pointer; len: cint); cdecl;
var
  I: integer;
begin
  for I := 0 to len div SizeOf(SmallInt) - 1 do
    if PSmallInt(input)[I] <> 0 then
    begin
      inputDevice.LastSignal := GetTickCount64;
      inputDevice.RetriedSilence := false;
      Break;
    end;
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

var CaptureTagCounter: cardinal;

function OpenIdentifiedCapture(Name: PChar; var Spec: TSDL_AudioSpec;
  out Key, Serial: UTF8String; AllowedChanges: integer = 0): TSDL_AudioDeviceID;
const StreamHint = 'SDL_AUDIO_DEVICE_STREAM_NAME';
var
  Tag, Previous: UTF8String;
  Tagged: boolean;
begin
  Key := '';
  Serial := '';
  Tagged := false;
  if SDL_GetCurrentAudioDriver = 'pulseaudio' then
  begin
    Previous := SDL_GetHint(StreamHint);
    Inc(CaptureTagCounter);
    Tag := 'USCE-' + IntToHex(PtrUInt(@CaptureTagCounter), SizeOf(Pointer)*2) +
      '-' + IntToHex(GetTickCount64, 16) + '-' + IntToHex(CaptureTagCounter, 8);
    Tagged := SDL_SetHint(StreamHint, PChar(Tag));
  end;
  try
    // SDL opens paused. The caller verifies identity before unpausing.
    Result := SDL_OpenAudioDevice(Name, 1, @Spec, @Spec, AllowedChanges);
  finally
    if Tagged then SDL_SetHint(StreamHint, PChar(Previous));
  end;
  if (Result <> 0) and Tagged then GetPulseCaptureIdentity(Tag, Key, Serial);
end;

function TSDLInputDevice.Start(): boolean;
begin
  if NeedsReassignment then Exit(false);
  CaptureWanted := true;
  RetriedSilence := false;
  NextRetry := GetTickCount64 + 1000;
  Result := OpenCapture;
  if not Result then
    Log.LogError('Could not open input device "' + Name + '": ' + SDL_GetError, 'SDL');
end;

function TSDLInputDevice.OpenCapture(Reconnect: boolean): boolean;
var
  spec: TSDL_AudioSpec;
  I: integer;
  Candidate, Key, Serial: UTF8String;
begin
  Result := false;

  if DevID <= 0 then
  begin
    FillChar(spec, SizeOf(spec), 0);
    with spec do
    begin
      freq := Round(AudioFormat.SampleRate);
      format := AUDIO_S16SYS;
      channels := AudioFormat.Channels;
      callback := @MicrophoneCallback;
      userdata := pointer(Self);

      samples := 0;
      if Ini.InputDeviceConfig[CfgIndex].Latency > 0 then
        samples := 1 shl Round(Max(Log2(freq / 1000 * Ini.InputDeviceConfig[CfgIndex].Latency), 0));
    end;

    if Reconnect or (Identity <> '') then
    begin
      if Identity = '' then Exit;
      for I := 0 to SDL_GetNumAudioDevices(1) - 1 do
      begin
        Candidate := SDL_GetAudioDeviceName(I, 1);
        if (Candidate = '') or (CaptureNameFamily(Candidate) <> CaptureNameFamily(SDLName)) then Continue;
        DevID := OpenIdentifiedCapture(PChar(Candidate), spec, Key, Serial);
        if (DevID <> 0) and (Key = Identity) then Break;
        if DevID <> 0 then SDL_CloseAudioDevice(DevID);
        DevID := 0;
      end;
    end
    else if UseName then
      DevID := SDL_OpenAudioDevice(PChar(SDLName), 1, @spec, @spec, 0)
    else
      DevID := SDL_OpenAudioDevice(nil, 1, @spec, @spec, 0);
    if DevID > 0 then
    begin
      if Ini.InputDeviceConfig[CfgIndex].Latency > 0 then
        Log.LogStatus('InputDevice "' + Name + '" opened with ' +
                      IntToStr(spec.samples) + ' samples (' +
                      IntToStr(round(spec.samples * 1000 / spec.freq)) +
                      'ms) buffer', 'SDL');
      LastSignal := GetTickCount64;
      SDL_PauseAudioDevice(DevID, 0);
    end;
  end;

  Result := (DevID > 0);
end;

function TSDLInputDevice.Stop(): boolean;
begin
  CaptureWanted := false;
  Removed := false;
  if DevID <> 0 then SDL_CloseAudioDevice(DevID);
  DevID := 0;
  Result := true;
end;

procedure TSDLInputDevice.CheckCapture(Now: QWord);
var
  Reopen: boolean;
  Channel: TCaptureBuffer;
begin
  if not CaptureWanted then Exit;
  if DevID <> 0 then
  begin
    Reopen := Removed or (SDL_GetAudioDeviceStatus(DevID) = SDL_AUDIO_STOPPED);
    if not Reopen then
    begin
      // Some SDL backends keep a disconnected stream open and deliver zeros.
      // Try once per silent period so a muted mic does not repeatedly reopen.
      SDL_LockAudioDevice(DevID);
      Reopen := not RetriedSilence and (Now >= LastSignal + 1500);
      if Reopen then RetriedSilence := true;
      SDL_UnlockAudioDevice(DevID);
    end;
    if not Reopen then Exit;
    SDL_CloseAudioDevice(DevID);
    DevID := 0;
    Removed := false;
    for Channel in CaptureChannel do
      if Assigned(Channel) then Channel.Clear;
    Log.LogStatus('Reopening SDL input device "' + Name + '"', 'SDL');
  end;
  if Now < NextRetry then Exit;
  NextRetry := Now + 1000;
  if Identity = '' then
  begin
    CaptureWanted := false;
    NeedsReassignment := true;
    Log.LogStatus('Cannot identify SDL input "' + Name +
      '" after disconnect. Reassign it in Recording Settings.', 'SDL');
    Exit;
  end;
  if OpenCapture(true) then
    Log.LogStatus('SDL input device "' + Name + '" reopened', 'SDL');
end;

var
  NextCaptureCheck: QWord;

procedure CheckSDLCaptureDevices;
var
  Device: TAudioInputDevice;
  Now: QWord;
begin
  if not Assigned(AudioInputProcessor) then Exit;
  Now := GetTickCount64;
  if Now < NextCaptureCheck then Exit;
  NextCaptureCheck := Now + 250;
  for Device in AudioInputProcessor.DeviceList do
    if Device is TSDLInputDevice then TSDLInputDevice(Device).CheckCapture(Now);
end;

procedure SDLCaptureDeviceRemoved(DeviceID: cardinal);
var
  Device: TAudioInputDevice;
begin
  if not Assigned(AudioInputProcessor) then Exit;
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
  SDLName, Identity, Serial: UTF8String;
begin
  Result := false;

  Log.LogInfo('Using ' + SDL_GetCurrentAudioDriver + ' driver', 'SDL');

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
    if (SDLName <> '') then
      dev := OpenIdentifiedCapture(PChar(SDLName), spec, Identity, Serial,
        SDL_AUDIO_ALLOW_FREQUENCY_CHANGE or SDL_AUDIO_ALLOW_CHANNELS_CHANGE)
    else
      dev := SDL_OpenAudioDevice(name, 1, @spec, @spec,
        SDL_AUDIO_ALLOW_FREQUENCY_CHANGE or SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
    if dev < 1 then
      continue;

    SDL_CloseAudioDevice(dev);

    device := TSDLInputDevice.Create();
    device.Name := deviceName;
    device.UseName := SDLName <> '';
    device.SDLName := SDLName;
    device.Identity := Identity;
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
