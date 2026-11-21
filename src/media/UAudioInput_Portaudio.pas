{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/media/UAudioInput_Portaudio.pas $
 * $Id: UAudioInput_Portaudio.pas 2665 2010-10-14 08:00:23Z k-m_schindler $
 *}

unit UAudioInput_Portaudio;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I ../switches.inc}

uses
  Classes,
  SysUtils,
  UMusic;

implementation

uses
  {$IFDEF UsePortmixer}
  portmixer,
  {$ENDIF}
  portaudio,
{$IFDEF LINUX}
  Dynlibs,
  UUSBCaptureIdentity,
{$ENDIF}
{$IFDEF DARWIN}
  MacOSAll,
{$ENDIF}
  ctypes,
  UAudioCore_Portaudio,
  UUnicodeUtils,
  UTextEncoding,
  UIni,
  ULog,
  UMain,
  URecord;

type
  TAudioInput_Portaudio = class(TAudioInputBase)
    private
      AudioCore: TAudioCore_Portaudio;
      function EnumDevices(): boolean;
    public
      function GetName: string; override;
      function InitializeRecord(ScanMode: TAudioInputScanMode): boolean; override;
      function FinalizeRecord: boolean; override;
  end;

  TPortaudioInputDevice = class(TAudioInputDevice)
    private
      RecordStream: PPaStream;
      {$IFDEF UsePortmixer}
      Mixer: PPxMixer;
      {$ENDIF}
      PaDeviceIndex:  TPaDeviceIndex;
{$IF Defined(LINUX) or Defined(DARWIN)}
      CaptureIdentity, CaptureModel: UTF8String;
      ActiveIdentity, ActiveAttachment: UTF8String;
      CapturePCM, ActivePCM: integer;
      ActiveIndex: TPaDeviceIndex;
      CaptureWanted: boolean;
      NextRetry: QWord;
      function CaptureAvailable(Index: TPaDeviceIndex; const Identity, Attachment: UTF8String;
        PCM: integer; Verified: boolean): boolean;
      function Reopen(): boolean;
      procedure CheckCapture(Now: System.QWord); override;
{$ENDIF}
      function StartDevice(Index: TPaDeviceIndex; AllowTwin: boolean): boolean;
      function Open(Index: TPaDeviceIndex; AllowTwin: boolean): boolean;
    public
      function Close(): boolean;
      function Start(): boolean; override;
      function Stop():  boolean; override;

      function DetermineInputLatency(Info: PPaDeviceInfo): TPaTime;

      function GetVolume(): single;        override;
      procedure SetVolume(Volume: single); override;
  end;

function MicrophoneCallback(input: pointer; output: pointer; frameCount: culong;
      timeInfo: PPaStreamCallbackTimeInfo; statusFlags: TPaStreamCallbackFlags;
      inputDevice: TAudioInputDevice): cint; cdecl; forward;

function MicrophoneTestCallback(input: pointer; output: pointer; frameCount: culong;
      timeInfo: PPaStreamCallbackTimeInfo; statusFlags: TPaStreamCallbackFlags;
      inputDevice: pointer): cint; cdecl; forward;

{**
 * Converts a string returned by Portaudio into UTF8.
 * If the string already is in UTF8 no conversion is performed, otherwise
 * the local encoding is used. 
 *}
function ConvertPaStringToUTF8(const Str: RawByteString): UTF8String;
begin
  if (IsUTF8String(Str)) then
    Result := Str
  else
    Result := DecodeStringUTF8(Str, encLocale);  
end;


{ TPortaudioInputDevice }

function TPortaudioInputDevice.DetermineInputLatency(Info: PPaDeviceInfo): TPaTime;
begin
  if (Ini.InputDeviceConfig[CfgIndex].Latency <> -1) then
  begin
    // autodetection off -> set user latency
    Result := Ini.InputDeviceConfig[CfgIndex].Latency / 1000
  end
  else
  begin
    // on vista and xp the defaultLowInputLatency may be set to 0 but it works.
    // TODO: correct too low latencies (what is a too low latency, maybe < 10ms?)
    // TODO: retry with input-latency set to 20ms (defaultLowInputLatency might
    //       not be set correctly in OSS)

    // FIXME: according to the portaudio headers defaultHighInputLatency (approx. 40ms) is
    // for robust non-interactive  applications and defaultLowInputLatency (approx. 15ms)
    // for interactive performance.
    // We need defaultLowInputLatency here but this setting is far too buggy. If the callback
    // does not return quickly the stream will be stuck after returning from the callback
    // and the callback will not be called anymore and mic-capturing stops.
    // Audacity (in AudioIO.cpp) uses defaultHighInputLatency if software playthrough is on
    // and even higher latencies (100ms) without playthrough so this should be ok for now.
    //Result := Info^.defaultLowInputLatency;
    Result := Info^.defaultHighInputLatency;
  end;
end;

{$IFDEF LINUX}
var
  ALSAExtensionLibrary: TLibHandle;
  ALSAExtensionChecked: boolean;
  PaAlsaGetInputCard: function(Stream: PPaStream; out Card: cint): TPaError; cdecl;

// PortAudio's ALSA hardware descriptors end in (hw:C,D) or (plughw:C,D).
// Arbitrary ALSA aliases do not identify a distinct hardware PCM.
function ALSAHardwareSuffix(const Name: UTF8String; out Card, PCM: integer): integer;
var
  Start, Comma: integer;
  Address, CardText, PCMText: UTF8String;
begin
  Result := 0;
  Start := LastDelimiter('(', Name);
  if (Start < 2) or (Name[Start - 1] <> ' ') or (Name[Length(Name)] <> ')') then Exit;
  Address := Copy(Name, Start + 1, Length(Name) - Start - 1);
  if Copy(Address, 1, 3) = 'hw:' then
    Delete(Address, 1, 3)
  else if Copy(Address, 1, 7) = 'plughw:' then
    Delete(Address, 1, 7)
  else
    Exit;
  Comma := Pos(',', Address);
  if Comma = 0 then Exit;
  CardText := Copy(Address, 1, Comma - 1);
  PCMText := Copy(Address, Comma + 1, MaxInt);
  if TryStrToInt(CardText, Card) and (Card >= 0) and (IntToStr(Card) = CardText) and
     TryStrToInt(PCMText, PCM) and (PCM >= 0) and (IntToStr(PCM) = PCMText) then
    Result := Start - 1;
end;

function ALSACaptureIdentity(Stream: PPaStream; Device: PPaDeviceInfo;
  out Serial, Model, Attachment: UTF8String; out PCM: integer): UTF8String;
var
  Host: PPaHostApiInfo;
  Card: cint;
  DeviceCard, DevicePCM: integer;
begin
  Result := '';
  Serial := '';
  Model := '';
  Attachment := '';
  PCM := -1;
  if Device = nil then Exit;
  Host := Pa_GetHostApiInfo(Device^.hostApi);
  if (Host = nil) or (Host^._type <> paALSA) then Exit;
  if not ALSAExtensionChecked then
  begin
    ALSAExtensionChecked := true;
    ALSAExtensionLibrary := LoadLibrary('libportaudio.so.2');
    if ALSAExtensionLibrary = NilHandle then
      ALSAExtensionLibrary := LoadLibrary(LibName);
    if ALSAExtensionLibrary <> NilHandle then
      @PaAlsaGetInputCard := GetProcedureAddress(ALSAExtensionLibrary,
        'PaAlsa_GetStreamInputCard');
    if not Assigned(PaAlsaGetInputCard) then
      Log.LogInfo('ALSA capture identity unavailable: missing PaAlsa_GetStreamInputCard', 'PortAudio');
  end;
  if not Assigned(PaAlsaGetInputCard) then Exit;
  Card := -1;
  if (PaAlsaGetInputCard(Stream, Card) <> paNoError) or (Card < 0) then Exit;
  Result := USBCaptureIdentity(Card, Serial, Model, Attachment);
  if (ALSAHardwareSuffix(Device^.name, DeviceCard, DevicePCM) <> 0) and (DeviceCard = Card) then
    PCM := DevicePCM;
end;
{$ENDIF}

{$IFDEF DARWIN}
{$linkframework CoreAudio}
function PaMacCore_GetStreamInputDevice(Stream: PPaStream): cuint32; cdecl; external LibName;
{$ENDIF}

{$IF Defined(LINUX) or Defined(DARWIN)}
function VerifiedCaptureIdentity(Stream: PPaStream; Device: PPaDeviceInfo;
  out Serial, Model, Attachment: UTF8String; out PCM: integer): UTF8String;
{$IFDEF DARWIN}
var
  Host: PPaHostApiInfo;
  DeviceID, Size, Alive: UInt32;
  Address: AudioObjectPropertyAddress;
  UID: CFStringRef;
  Buffer: array[0..1023] of AnsiChar;
{$ENDIF}
begin
{$IFDEF LINUX}
  Result := ALSACaptureIdentity(Stream, Device, Serial, Model, Attachment, PCM);
{$ELSE}
  Result := '';
  Serial := '';
  Model := '';
  Attachment := '';
  PCM := -1;
  if Device = nil then Exit;
  Host := Pa_GetHostApiInfo(Device^.hostApi);
  if (Host = nil) or (Host^._type <> paCoreAudio) then Exit;
  DeviceID := PaMacCore_GetStreamInputDevice(Stream);
  if DeviceID = 0 then Exit;
  Address.mScope := kAudioObjectPropertyScopeGlobal;
  Address.mElement := 0;
  Address.mSelector := kAudioDevicePropertyDeviceIsAlive;
  Size := SizeOf(Alive);
  if (AudioObjectGetPropertyData(DeviceID, Address, 0, nil, Size, @Alive) <> 0) or
     (Alive = 0) then Exit;
  Address.mSelector := kAudioDevicePropertyDeviceUID;
  UID := nil;
  Size := SizeOf(UID);
  if (AudioObjectGetPropertyData(DeviceID, Address, 0, nil, Size, @UID) <> 0) or
     (UID = nil) then Exit;
  try
    // A USB UID can encode a port instead of a serial. Use it with the
    // live Core Audio object for a verified match.
    if CFStringGetCString(UID, @Buffer[0], SizeOf(Buffer), kCFStringEncodingUTF8) and
       (Buffer[0] <> #0) then
      Result := IntToStr(DeviceID) + ':' + UTF8String(PAnsiChar(@Buffer[0]));
  finally
    CFRelease(UID);
  end;
{$ENDIF}
end;
{$ENDIF}

{$IF Defined(LINUX) or Defined(DARWIN)}
function CapturePCMsOverlap(First, Second: integer): boolean;
begin
  // An alias with an unknown PCM may refer to the same capture endpoint.
  Result := (First < 0) or (Second < 0) or (First = Second);
end;
{$ENDIF}

function TPortaudioInputDevice.Open(Index: TPaDeviceIndex; AllowTwin: boolean): boolean;
var
  Error:       TPaError;
  inputParams: TPaStreamParameters;
  deviceInfo:  PPaDeviceInfo;
  StreamInfo : PPaStreamInfo;
{$IF Defined(LINUX) or Defined(DARWIN)}
  Serial, Identity, Model, Attachment: UTF8String;
  PCM: integer;
  Verified: boolean;
{$ENDIF}
  {$IFDEF UsePortmixer}
  SourceIndex: integer;
  {$ENDIF}
begin
  Result := false;

  // get input latency info
  deviceInfo := Pa_GetDeviceInfo(Index);
  if (deviceInfo = nil) or (deviceInfo^.maxInputChannels < AudioFormat.Channels) then Exit;
{$IF Defined(LINUX) or Defined(DARWIN)}
  if not CaptureAvailable(Index, '', '', -1, true) then Exit;
{$ENDIF}

  // set input stream parameters
  with inputParams do
  begin
    device := Index;
    channelCount := AudioFormat.Channels;
    sampleFormat := paInt16;
    suggestedLatency := DetermineInputLatency(deviceInfo);
    hostApiSpecificStreamInfo := nil;
  end;

  Log.LogStatus('Open ' + deviceInfo^.name, 'Portaudio');

  // open input stream
  Error := Pa_OpenStream(RecordStream, @inputParams, nil,
      AudioFormat.SampleRate,
      paFramesPerBufferUnspecified, paNoFlag,
      @MicrophoneCallback, pointer(Self));
  if (Error <> paNoError) then
  begin
    RecordStream := nil;
    Log.LogError('Error opening stream: ' + Pa_GetErrorText(Error), 'TPortaudioInputDevice.Open');
    Exit;
  end;

{$IF Defined(LINUX) or Defined(DARWIN)}
  Identity := VerifiedCaptureIdentity(RecordStream, deviceInfo, Serial, Model, Attachment, PCM);
  Verified := (CaptureIdentity <> '') and (Identity = CaptureIdentity);
  if not CapturePCMsOverlap(CapturePCM, PCM) or
     (not Verified and
      (((CaptureIdentity <> '') and not AllowTwin) or
       ((CaptureModel <> '') and (CaptureModel <> Model)))) or
     not CaptureAvailable(Index, Identity, Attachment, PCM, Verified) then
  begin
    Close();
    Exit;
  end;
  ActiveIndex := Index;
  ActiveIdentity := Identity;
  ActiveAttachment := Attachment;
  ActivePCM := PCM;
{$ENDIF}
  StreamInfo := Pa_GetStreamInfo(RecordStream);
  if (StreamInfo <> nil) then
    Log.LogStatus('Latency of ' + deviceInfo^.name + ': ' +
                  floatToStr(StreamInfo^.inputLatency * 1000) +
                  'ms (requested: ' +
                  floatToStr(inputParams.suggestedLatency * 1000) +
                  'ms)', 'Portaudio');

  {$IFDEF UsePortmixer}
    // open default mixer
    Mixer := Px_OpenMixer(RecordStream, 0);
    if (Mixer = nil) then
    begin
      Log.LogError('Error opening mixer: ' + Pa_GetErrorText(Error), 'TPortaudioInputDevice.Open');
    end
    else
    begin
      // save current source selection and select new source
      SourceIndex := Ini.InputDeviceConfig[CfgIndex].Input-1;
      if (SourceIndex = -1) then
      begin
        // nothing to do if default source is used
        SourceRestore := -1;
      end
      else
      begin
        // store current source-index and select new source
        SourceRestore := Px_GetCurrentInputSource(Mixer); // -1 in error case
        Px_SetCurrentInputSource(Mixer, SourceIndex);
      end;
    end;
  {$ENDIF}

  Result := true;
end;

function TPortaudioInputDevice.Start(): boolean;
begin
  // recording already started -> stop first
  if (RecordStream <> nil) then
    Stop();

{$IF Defined(LINUX) or Defined(DARWIN)}
  CaptureWanted := true;
  NextRetry := GetTickCount64 + 1000;
{$ENDIF}
  Result := StartDevice(PaDeviceIndex, false);
end;

function TPortaudioInputDevice.StartDevice(Index: TPaDeviceIndex; AllowTwin: boolean): boolean;
var
  Error: TPaError;
begin
  Result := false;
  if not Open(Index, AllowTwin) then Exit;

  // start capture
  Error := Pa_StartStream(RecordStream);
  if (Error <> paNoError) then
  begin
    Log.LogError('Error starting stream: ' + Pa_GetErrorText(Error), 'TPortaudioInputDevice.Start');
    Close();
    RecordStream := nil;
    Exit;
  end;

  Result := true;
end;

function TPortaudioInputDevice.Stop(): boolean;
var
  Error: TPaError;
begin
{$IF Defined(LINUX) or Defined(DARWIN)}
  CaptureWanted := false;
{$ENDIF}
  Result := false;

  if (RecordStream = nil) then
    Exit;

  // Note: do NOT call Pa_StopStream here!
  // It gets stuck on devices with non-working callback as Pa_StopStream
  // waits until all buffers have been handled (which never occurs in that case).
  Error := Pa_AbortStream(RecordStream);
  if (Error <> paNoError) then
  begin
    Log.LogError('Pa_AbortStream: ' + Pa_GetErrorText(Error), 'TPortaudioInputDevice.Stop');
  end;

  Result := Close();
end;

function TPortaudioInputDevice.Close(): boolean;
var
  Error: TPaError;
begin
  {$IFDEF UsePortmixer}
    if (Mixer <> nil) then
    begin
      // restore source selection
      if (SourceRestore >= 0) then
      begin
        Px_SetCurrentInputSource(Mixer, SourceRestore);
      end;

      // close mixer
      Px_CloseMixer(Mixer);
      Mixer := nil;
    end;
  {$ENDIF}

  Error := Pa_CloseStream(RecordStream);
  if (Error <> paNoError) then
  begin
    Log.LogError('Pa_CloseStream: ' + Pa_GetErrorText(Error), 'TPortaudioInputDevice.Close');
    Result := false;
  end
  else
  begin
    Result := true;
  end;

  RecordStream := nil;
end;

{$IF Defined(LINUX) or Defined(DARWIN)}
function TPortaudioInputDevice.CaptureAvailable(Index: TPaDeviceIndex;
  const Identity, Attachment: UTF8String; PCM: integer; Verified: boolean): boolean;
var
  Device: TAudioInputDevice;
  Other: TPortaudioInputDevice;
begin
  for Device in AudioInputProcessor.DeviceList do
    if (Device <> Self) and (Device is TPortaudioInputDevice) then
    begin
      Other := TPortaudioInputDevice(Device);
      if (Other.RecordStream <> nil) and
         ((Other.ActiveIndex = Index) or
          (CapturePCMsOverlap(Other.ActivePCM, PCM) and
           (((Identity <> '') and (Other.ActiveIdentity = Identity)) or
            ((Attachment <> '') and (Other.ActiveAttachment = Attachment))))) then Exit(false);
      if not Verified and Other.CaptureWanted and
         ((Other.PaDeviceIndex = Index) or
          ((Identity <> '') and (Other.CaptureIdentity = Identity) and
           CapturePCMsOverlap(Other.CapturePCM, PCM))) then Exit(false);
    end;
  Result := true;
end;

function CaptureName(Info: PPaDeviceInfo): UTF8String;
{$IFDEF LINUX}
var
  Suffix, Card, PCM: integer;
{$ENDIF}
begin
  Result := ConvertPaStringToUTF8(Info^.name);
{$IFDEF LINUX}
  Suffix := ALSAHardwareSuffix(Result, Card, PCM);
  if Suffix > 0 then SetLength(Result, Suffix - 1);
{$ENDIF}
end;

function TPortaudioInputDevice.Reopen(): boolean;
var
  Original, Candidate: PPaDeviceInfo;
  Index, Pass: integer;
  AllowTwin: boolean;
begin
  Result := false;
  Original := Pa_GetDeviceInfo(PaDeviceIndex);
  if Original = nil then Exit;
  // PortAudio exposes a snapshot. Try the original index first in each pass,
  // then consider the other entries with the same name in that host API.
  for Pass := 0 to Ord(CaptureIdentity <> '') do
  begin
    AllowTwin := Pass > 0;
    if StartDevice(PaDeviceIndex, AllowTwin) then Exit(true);
    for Index := 0 to Pa_GetDeviceCount() - 1 do
    begin
      if Index = PaDeviceIndex then Continue;
      Candidate := Pa_GetDeviceInfo(Index);
      if (Candidate <> nil) and (Candidate^.hostApi = Original^.hostApi) and
         (CaptureName(Candidate) = CaptureName(Original)) and
         StartDevice(Index, AllowTwin) then Exit(true);
    end;
  end;
end;

procedure TPortaudioInputDevice.CheckCapture(Now: System.QWord);
begin
  if not CaptureWanted then Exit;
  if RecordStream <> nil then
  begin
    if (Pa_IsStreamActive(RecordStream) = 1)
       {$IFDEF LINUX}
       and ((Now < NextRetry) or (ActiveAttachment = '') or USBInstanceAttached(ActiveAttachment))
       {$ENDIF}
       then
    begin
      if Now >= NextRetry then NextRetry := Now + 1000;
      Exit;
    end;
    Stop();
    CaptureWanted := true;
    ResetCaptureAnalysis;
    Log.LogStatus('Input interrupted: "' + Name + '"', 'PortAudio');
  end;
  if Now < NextRetry then Exit;
  NextRetry := Now + 1000;
  if Reopen() then
    Log.LogStatus('Input reopened: "' + Name + '"', 'PortAudio');
end;
{$ENDIF}

function TPortaudioInputDevice.GetVolume(): single;
begin
  Result := 0;
  {$IFDEF UsePortmixer}
    if (Mixer <> nil) then
      Result := Px_GetInputVolume(Mixer);
  {$ENDIF}
end;

procedure TPortaudioInputDevice.SetVolume(Volume: single);
begin
  {$IFDEF UsePortmixer}
    if (Mixer <> nil) then
    begin
      // clip to valid range
      if (Volume > 1.0) then
        Volume := 1.0
      else if (Volume < 0) then
        Volume := 0;
      Px_SetInputVolume(Mixer, Volume);
    end;
  {$ENDIF}
end;


{ TAudioInput_Portaudio }

function TAudioInput_Portaudio.GetName: String;
begin
  result := 'Portaudio';
end;

function TAudioInput_Portaudio.EnumDevices(): boolean;
var
  i:            integer;
  deviceName:   UTF8String;
  paApiIndex:   TPaHostApiIndex;
  paApiInfo:    PPaHostApiInfo;
  paDeviceIndex:TPaDeviceIndex;
  paDeviceInfo: PPaDeviceInfo;
  channelCnt:   integer;
  deviceIndex:  integer;
  err:          TPaError;
  errMsg:       string;
  paDevice:     TPortaudioInputDevice;
  inputParams:  TPaStreamParameters;
  stream:       PPaStream;
  streamInfo:   PPaStreamInfo;
  sampleRate:   double;
  latency:      TPaTime;
  unifiedDeviceName: UTF8String;
  {$IF Defined(LINUX) or Defined(DARWIN)}
  Attachment:   UTF8String;
  {$ENDIF}
  {$IFDEF UsePortmixer}
  mixer:        PPxMixer;
  sourceCnt:    integer;
  sourceIndex:  integer;
  sourceName:   UTF8String;
  {$ENDIF}
const
  MIN_TEST_LATENCY = 100 / 1000; // min. test latency of 100 ms to avoid removal of working devices
begin
  Result := false;

  // choose the best available Audio-API
  paApiIndex := AudioCore.GetPreferredApiIndex();
  if (paApiIndex = -1) then
  begin
    Log.LogError('No working Audio-API found', 'TAudioInput_Portaudio.EnumDevices');
    Exit;
  end;

  paApiInfo := Pa_GetHostApiInfo(paApiIndex);

  deviceIndex := 0;

  // init array-size to max. input-devices count
  SetLength(AudioInputProcessor.DeviceList, paApiInfo^.deviceCount);
  for i:= 0 to High(AudioInputProcessor.DeviceList) do
  begin
    // convert API-specific device-index to global index
    paDeviceIndex := Pa_HostApiDeviceIndexToDeviceIndex(paApiIndex, i);
    paDeviceInfo := Pa_GetDeviceInfo(paDeviceIndex);

    channelCnt := paDeviceInfo^.maxInputChannels;

    // current device is no input device -> skip
    if (channelCnt <= 0) then
      continue;

    // workaround for https://github.com/alsa-project/alsa-plugins/issues/13
    if CompareStr(paDeviceInfo^.name, 'vdownmix') = 0 then
    begin
      Log.LogWarn('Skipping vdownmix device because of alsa-plugins Github issue 13', 'Portaudio.EnumDevices');
      continue;
    end;

    // retrieve device-name before running expensive tests
    deviceName := ConvertPaStringToUTF8(paDeviceInfo^.name);
    unifiedDeviceName := UnifyDeviceName(deviceName, i);
    if not ShouldProbeDevice(unifiedDeviceName) then
      continue;

    paDevice := TPortaudioInputDevice.Create();
    AudioInputProcessor.DeviceList[deviceIndex] := paDevice;

    paDevice.Name := unifiedDeviceName;
    Log.LogStatus('Attempting to configure InputDevice "' + paDevice.Name + '"', 'Portaudio.EnumDevices');
    paDevice.PaDeviceIndex := paDeviceIndex;

    sampleRate := paDeviceInfo^.defaultSampleRate;

    // use a stable (high) latency so we do not remove working devices
    if (paDeviceInfo^.defaultHighInputLatency > MIN_TEST_LATENCY) then
      latency := paDeviceInfo^.defaultHighInputLatency
    else
      latency := MIN_TEST_LATENCY;

    // setup desired input parameters
    with inputParams do
    begin
      device := paDeviceIndex;
      channelCount := channelCnt;
      sampleFormat := paInt16;
      suggestedLatency := latency;
      hostApiSpecificStreamInfo := nil;
    end;

    // check souncard and adjust sample-rate
    if (not AudioCore.TestDevice(@inputParams, nil, sampleRate)) then
    begin
      // ignore device if it does not work
      Log.LogError('Device "'+paDevice.Name+'" does not work',
                   'TAudioInput_Portaudio.EnumDevices');
      paDevice.Free();
      continue;
    end;

    // open device for further info
    err := Pa_OpenStream(stream, @inputParams, nil, sampleRate,
        paFramesPerBufferUnspecified, paNoFlag, @MicrophoneTestCallback, nil);
    if (err <> paNoError) then
    begin
      // unable to open device -> skip
      errMsg := Pa_GetErrorText(err);
      Log.LogError('Device error: "'+ deviceName +'" ('+ errMsg +')',
                   'TAudioInput_Portaudio.EnumDevices');
      paDevice.Free();
      continue;
    end;

    // adjust sample-rate (might be changed by portaudio)
    streamInfo := Pa_GetStreamInfo(stream);
    if (streamInfo <> nil) then
    begin
      if (sampleRate <> streamInfo^.sampleRate) then
      begin
        Log.LogStatus('Portaudio changed Samplerate from ' + FloatToStr(sampleRate) +
            ' to ' + FloatToStr(streamInfo^.sampleRate),
            'TAudioInput_Portaudio.InitializeRecord');
        sampleRate := streamInfo^.sampleRate;
      end;
    end;
    
    // create audio-format info and resize capture-buffer array
    paDevice.AudioFormat := TAudioFormatInfo.Create(
        channelCnt,
        sampleRate,
        asfS16
    );
    SetLength(paDevice.CaptureChannel, paDevice.AudioFormat.Channels);

    Log.LogStatus('InputDevice "'+paDevice.Name+'"@' +
        IntToStr(paDevice.AudioFormat.Channels)+'x'+
        FloatToStr(paDevice.AudioFormat.SampleRate)+'Hz ('+
        FloatTostr(inputParams.suggestedLatency)+'sec)' ,
        'Portaudio.EnumDevices');

    // portaudio does not provide a source-type check
    paDevice.MicSource := -1;
    paDevice.SourceRestore := -1;

    // add a virtual default source (will not change mixer-settings)
    SetLength(paDevice.Source, 1);
    paDevice.Source[0].Name := DEFAULT_SOURCE_NAME;

    {$IFDEF UsePortmixer}
      // use default mixer
      mixer := Px_OpenMixer(stream, 0);

      // get input count
      sourceCnt := Px_GetNumInputSources(mixer);
      SetLength(paDevice.Source, sourceCnt+1);

      // get input names
      for sourceIndex := 1 to sourceCnt do
      begin
        sourceName := Px_GetInputSourceName(mixer, sourceIndex-1);
        paDevice.Source[sourceIndex].Name := ConvertPaStringToUTF8(sourceName);
      end;

      Px_CloseMixer(mixer);
    {$ENDIF}

{$IF Defined(LINUX) or Defined(DARWIN)}
    paDevice.CaptureIdentity := VerifiedCaptureIdentity(stream, paDeviceInfo,
      paDevice.CaptureSerial, paDevice.CaptureModel, Attachment, paDevice.CapturePCM);
{$ENDIF}
    // close test-stream
    Pa_CloseStream(stream);

    Inc(deviceIndex);
  end;

  // adjust size to actual input-device count
  SetLength(AudioInputProcessor.DeviceList, deviceIndex);

  Log.LogStatus('#Input-Devices: ' + inttostr(deviceIndex), 'Portaudio');

  Result := true;
end;

function TAudioInput_Portaudio.InitializeRecord(ScanMode: TAudioInputScanMode): boolean;
begin
  Result := false;
  AudioCore := TAudioCore_Portaudio.GetInstance();

  // initialize portaudio
  if (not AudioCore.Initialize()) then
     Exit;
  PrepareDeviceScan(ScanMode);
  Result := EnumDevices();
end;

function TAudioInput_Portaudio.FinalizeRecord: boolean;
begin
  CaptureStop;
  if assigned(AudioCore) then
     AudioCore.Terminate();
  Result := inherited FinalizeRecord();
end;

{*
 * Portaudio input capture callback.
 *}
function MicrophoneCallback(input: pointer; output: pointer; frameCount: culong;
      timeInfo: PPaStreamCallbackTimeInfo; statusFlags: TPaStreamCallbackFlags;
      inputDevice: TAudioInputDevice): cint; cdecl;
var
  AudioFormat:             TAudioFormatInfo;
begin
  AudioFormat := inputDevice.AudioFormat;
  AudioInputProcessor.HandleMicrophoneData(input, frameCount * AudioFormat.FrameSize, inputDevice);
  result := paContinue;
end;

{*
 * Portaudio test capture callback.
 *}
function MicrophoneTestCallback(input: pointer; output: pointer; frameCount: culong;
      timeInfo: PPaStreamCallbackTimeInfo; statusFlags: TPaStreamCallbackFlags;
      inputDevice: pointer): cint; cdecl;
begin
  // this callback is called only once
  result := paAbort;
end;

initialization
  MediaManager.add(TAudioInput_Portaudio.Create);

end.
