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
  UPulseSources,
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
      UseName: boolean;
      SDLName: UTF8String; // name SDL currently uses for this device
      Port:    UTF8String; // where the device is plugged in ('' if unknown)
      CaptureWanted, Removed, RetriedSilence, ReopenFailed: boolean;
      LastSignal, NextRetry: QWord;
      function ResolveSDLName: boolean;
      function OpenCapture: boolean;
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

// removes the " (2)" SDL appends to devices with identical names
function StripDuplicateSuffix(const name: UTF8String): UTF8String;
var
  i: integer;
begin
  Result := name;
  i := Length(name);
  if (i < 4) or (name[i] <> ')') then
    Exit;
  Dec(i);
  while (i > 0) and (name[i] in ['0'..'9']) do
    Dec(i);
  if (i > 1) and (i < Length(name) - 1) and (name[i] = '(') and (name[i-1] = ' ') then
    Result := Copy(name, 1, i - 2);
end;

type
  TUTF8StringArray = array of UTF8String;

{*
 * Lists SDL's recording devices and, where possible, the port each of them
 * is plugged into ('' if unknown).
 * SDL does not tell us the port, the sound server does. Both list the devices
 * in the same order, so the n-th SDL device with a certain description is the
 * n-th device with that description of the sound server.
 *}
procedure ListCaptureDevices(out names, ports: TUTF8StringArray);
var
  i, j, k: integer;
  count:   integer;
  sdlDev:  PChar;
  sources: TPulseSourceArray;
  base:    UTF8String;
  matches: array of integer;
  usable:  boolean;
begin
  // this also refreshes SDL's device list
  count := SDL_GetNumAudioDevices(1);
  SetLength(names, 0);
  for i := 0 to count - 1 do
  begin
    sdlDev := SDL_GetAudioDeviceName(i, 1);
    if sdlDev = nil then
      continue;
    SetLength(names, Length(names) + 1);
    names[High(names)] := sdlDev;
  end;

  SetLength(ports, Length(names));
  for i := 0 to High(ports) do
    ports[i] := '';

  if StrPas(SDL_GetCurrentAudioDriver) <> 'pulseaudio' then
    Exit;
  if not GetPulseSources(sources) then
    Exit;

  for i := 0 to High(names) do
  begin
    base := StripDuplicateSuffix(names[i]);

    // handle every description once, at its first device
    usable := true;
    for j := 0 to i - 1 do
      if StripDuplicateSuffix(names[j]) = base then
        usable := false;
    if not usable then
      continue;

    SetLength(matches, 0);
    for j := 0 to High(sources) do
    begin
      if sources[j].Description <> base then
        continue;
      // the port has to be known and must identify the device
      if sources[j].BusPath = '' then
        usable := false;
      for k := 0 to High(matches) do
        if sources[matches[k]].BusPath = sources[j].BusPath then
          usable := false;
      SetLength(matches, Length(matches) + 1);
      matches[High(matches)] := j;
    end;

    count := 0;
    for j := i to High(names) do
      if StripDuplicateSuffix(names[j]) = base then
        Inc(count);

    // while a device is (dis)appearing both lists may differ for a moment
    if (not usable) or (count <> Length(matches)) then
      continue;

    k := 0;
    for j := i to High(names) do
    begin
      if StripDuplicateSuffix(names[j]) = base then
      begin
        ports[j] := sources[matches[k]].BusPath;
        Inc(k);
      end;
    end;
  end;
end;

// Form of a bus path used in the device name, e.g. "09:00.0-usb-0:3:1.0".
// The controller stays part of it: the same port number exists once per
// USB controller.
function PortLabel(const port: UTF8String): UTF8String;
const
  PCI_PREFIX = 'pci-0000:';
begin
  Result := port;
  if Copy(Result, 1, Length(PCI_PREFIX)) = PCI_PREFIX then
    Delete(Result, 1, Length(PCI_PREFIX));
end;

function FindDeviceConfig(const name: UTF8String): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(Ini.InputDeviceConfig) do
    if Ini.InputDeviceConfig[i].Name = name then
    begin
      Result := i;
      Exit;
    end;
end;

{*
 * Makes sure SDLName is a name SDL currently knows.
 * Identical devices only differ by a number SDL appends in the order they
 * show up, and SDL keeps counting: after a reconnect "Mic (2)" comes back
 * as "Mic (3)". If we know the port of the device we look for the device at
 * that port. Otherwise, if our name is gone, we take a device with the same
 * base name that is not used by another input device.
 *}
function TSDLInputDevice.ResolveSDLName: boolean;
var
  i:      integer;
  names:  TUTF8StringArray;
  ports:  TUTF8StringArray;
  other:  TAudioInputDevice;
  taken:  boolean;
begin
  Result := false;
  ListCaptureDevices(names, ports);

  if Port <> '' then
  begin
    for i := 0 to High(names) do
      if ports[i] = Port then
      begin
        if names[i] <> SDLName then
          Log.LogStatus('InputDevice "' + Name + '" is now known to SDL as "' + names[i] + '"', 'SDL');
        SDLName := names[i];
        Result := true;
        Exit;
      end;
    // Nothing is listed at our port. Either the device is gone or the ports
    // could not be read this time, so only an unchanged name is safe to use.
    for i := 0 to High(names) do
      if (names[i] = SDLName) and (ports[i] = '') then
        Result := true;
    Exit;
  end;

  for i := 0 to High(names) do
    if names[i] = SDLName then
    begin
      Result := true;
      Exit;
    end;

  for i := 0 to High(names) do
  begin
    if StripDuplicateSuffix(names[i]) <> StripDuplicateSuffix(SDLName) then
      continue;

    taken := false;
    for other in AudioInputProcessor.DeviceList do
      if (other <> Self) and (other is TSDLInputDevice) and
         (TSDLInputDevice(other).SDLName = names[i]) then
        taken := true;

    if not taken then
    begin
      Log.LogStatus('InputDevice "' + Name + '" is now known to SDL as "' + names[i] + '"', 'SDL');
      SDLName := names[i];
      Result := true;
      Exit;
    end;
  end;
end;

function TSDLInputDevice.Start(): boolean;
begin
  CaptureWanted := true;
  ReopenFailed := false;
  RetriedSilence := false;
  NextRetry := GetTickCount64 + 1000;
  Result := OpenCapture;
  if not Result then
    Log.LogError('Could not open input device "' + Name + '": ' + SDL_GetError, 'SDL');
end;

function TSDLInputDevice.OpenCapture: boolean;
var
  devName: PChar;
  spec:    TSDL_AudioSpec;
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

    devName := nil;
    if UseName then
    begin
      if not ResolveSDLName then
      begin
        SDL_SetError('device not found');
        Exit;
      end;
      devName := PChar(SDLName);
    end;

    DevID := SDL_OpenAudioDevice(devName, 1, @spec, @spec, 0);
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
    Log.LogStatus('Reopening SDL input device "' + Name + '"', 'SDL');
  end;
  if Now < NextRetry then Exit;
  NextRetry := Now + 1000;
  if OpenCapture then
  begin
    ReopenFailed := false;
    Log.LogStatus('SDL input device "' + Name + '" reopened', 'SDL');
  end
  else if not ReopenFailed then
  begin
    // once per outage, the attempt is repeated every second
    ReopenFailed := true;
    Log.LogError('Could not reopen input device "' + Name + '": ' + SDL_GetError + ', retrying', 'SDL');
  end;
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
  names, ports: TUTF8StringArray;
  j:            integer;
  port:         UTF8String;
  portName:     UTF8String;
  hasTwin:      boolean;
  cfgIndex:     integer;
  cfgChanged:   boolean;
begin
  Result := false;

  Log.LogInfo('Using ' + SDL_GetCurrentAudioDriver + ' driver', 'SDL');

  cfgChanged := false;
  ListCaptureDevices(names, ports);
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

    deviceName := DEFAULT_SOURCE_NAME;
    port := '';
    if (name <> nil) then
    begin
      deviceName := name;
      hasTwin := false;
      for j := 0 to High(names) do
        if names[j] = deviceName then
          port := ports[j]
        else if StripDuplicateSuffix(names[j]) = StripDuplicateSuffix(deviceName) then
          hasTwin := true;

      if port <> '' then
      begin
        // Identical devices are named after the port they are plugged into.
        // SDL's own numbering depends on the order in which they showed up,
        // so the player assignment would not be stable between sessions.
        portName := StripDuplicateSuffix(deviceName) + ' [' + PortLabel(port) + ']';

        // Once a device was configured by port keep that name,
        // even while its twin is not connected.
        if hasTwin or (FindDeviceConfig(portName) >= 0) then
        begin
          if FindDeviceConfig(portName) < 0 then
          begin
            // carry over the assignment made with SDL's name
            cfgIndex := FindDeviceConfig(deviceName);
            if cfgIndex >= 0 then
            begin
              Ini.InputDeviceConfig[cfgIndex].Name := portName;
              cfgChanged := true;
              Log.LogStatus('InputDevice "' + deviceName + '" is now configured as "' + portName + '"', 'SDL');
            end;
          end;
          deviceName := portName;
        end;
      end;
    end;
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

    dev := SDL_OpenAudioDevice(name, 1, @spec, @spec, SDL_AUDIO_ALLOW_FREQUENCY_CHANGE or SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
    if dev < 1 then
      continue;

    SDL_CloseAudioDevice(dev);

    device := TSDLInputDevice.Create();
    device.Name := deviceName;
    device.UseName := false;
    if name <> nil then
    begin
      device.UseName := true;
      device.SDLName := name;
      device.Port := port;
    end;

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

  // keep the port based names, otherwise the assignment would be carried
  // over again on the next start, with whatever order the devices have then
  if cfgChanged then
    Ini.Save;

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
