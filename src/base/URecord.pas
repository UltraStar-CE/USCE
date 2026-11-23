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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/base/URecord.pas $
 * $Id: URecord.pas 2814 2011-04-06 23:31:15Z k-m_schindler $
 *}

unit URecord;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  Classes,
  Math,
  sdl2,
  SysUtils,
  UCommon,
  UMusic,
  UIni;

const
  BaseToneFreq = 440; // A4 concert pitch of 440 Hz
  NumHalftones = 49;  // C2 to C6 (1046.5023 Hz)
  ToneStringOctaveOffset = 2;
  MaxToneCandidates = 5;
  PhonePcmSampleRate = 48000;
  CaptureWindowSamples = 4096;
  CaptureHistorySamples = 2 * CaptureWindowSamples;

type
  // pitch detection algorithm (PDA)
  TPDAType = (
    PDA_AMDF,   // average magnitude difference function
    PDA_CAMDF  // circular average magnitude difference function
  );

  TFrequencyArray   = array[0..NumHalftones-1] of real;
  TDelayArray       = array[0..NumHalftones-1] of integer;
  TCorrelationArray = array[0..NumHalftones-1] of real;

  TToneCandidate = record
    ToneAbs: integer;
    Confidence: single;
    Correlation: real;
    Frequency: real;
  end;

  TCaptureBuffer = class
    private
      fVoiceStream: TAudioVoiceStream; // stream for voice passthrough
      fAnalysisBufferLock: PSDL_Mutex;
      fAudioFormat: TAudioFormatInfo;
      FLocalCaptureEndUs: int64;
      FLocalBlockUs: int64;
      FLocalSamples: integer;
      Frequencies: TFrequencyArray;
      Delays: TDelayArray;
      fToneCandidates: array[0..MaxToneCandidates-1] of TToneCandidate;
      fToneCandidateCount: integer;

      function GetToneString: string; // converts a tone to its string representation;
      function GetToneCandidate(Index: integer): TToneCandidate;

      procedure BoostBuffer(Buffer: PByteArray; Size: integer);
      procedure ProcessNewBuffer(Buffer: PByteArray; BufferSize: integer; AllowRecording: boolean = true;
        AllowBoost: boolean = true; CaptureEndUs: int64 = 0);

      procedure StartCapture(Format: TAudioFormatInfo);
      procedure StopCapture();

      procedure ResetToneDiagnostics;
      procedure SetFrequenciesAndDelays(SampleRate: double);
      procedure AnalyzeSamples(const Samples: array of smallint; Count: integer; SampleRate: double;
        Gain: integer = 1; MeasureBoost: boolean = false);
      function AnalysisGain: integer;
      // we call it to analyze sound by checking AMDF
      function AnalyzePitch(PDA: TPDAType; const Samples: array of smallint; Count: integer; SampleRate: double): boolean;
      // use this to check one frequency by AMDF
      function AverageMagnitudeDifference(const Samples: array of smallint; Count: integer): TCorrelationArray;
      function CircularAverageMagnitudeDifference(const Samples: array of smallint; Count: integer): TCorrelationArray;
      function ArrayIndexOfMinimum(const AValues: array of real): Integer;
      procedure UpdateToneCandidatesSimple(const Correlation: TCorrelationArray);
    public
      AnalysisBuffer: array of smallint;
      AnalysisBufferSize: integer; // number of samples of BufferArray to analyze

      MonitorOnly: boolean; // level preview: no voice playback or recording
      LogBuffer:   TMemoryStream;              // full buffer

      // pitch detection
      // TODO: remove ToneValid, set Tone/ToneAbs=-1 if invalid instead
      ToneValid: boolean;    // true if Tone contains a valid value (otherwise it contains noise)
      PhoneBoostProbeTone: integer;
      PhoneAboveHalfMeter: boolean;
      Tone:      integer;    // tone relative to one octave (e.g. C2=C3=C4). Range: 0-11
      ToneAbs:   integer;    // absolute (full range) tone (e.g. C2<>C3). Range: 0..NumHalftones-1
      RawToneValid: boolean;
      RawTone:      integer;
      RawToneAbs:   integer;
      LastInputTicks: QWord;
      LastInputBlockMs: double;
      LastAnalysisMicroseconds: double;
      PhoneCaptureGeneration: LongWord;
      PitchAlgorithm: TPDAType;

      // methods
      constructor Create;
      destructor Destroy; override;

      procedure Clear;
      procedure ResetAnalysis;

      // use to analyze sound from buffers to get new pitch
      procedure AnalyzeBuffer; overload;
      procedure AnalyzeBuffer(out WindowCenterUs: int64); overload;
      function AnalyzeLocalWindow(CenterUs: int64; Count: integer; out WaitUntilUs: int64): boolean;
      function HasLocalCapture: boolean;
      function AnalyzePhoneWindow(PlayerIndex: integer; CenterHostUs: Int64; WindowSamples: integer = 0;
        MeasureBoost: boolean = false): boolean;
      // Experimental native phone input, mono S16 at 48 kHz. Main thread only.
      procedure SubmitPhonePcm(Samples: pointer; Count: integer);
      procedure LockAnalysisBuffer();
      procedure UnlockAnalysisBuffer();

      function MaxSampleVolume: single; overload;
      function MaxSampleVolume(out Clipped: boolean): single; overload;
      property ToneString: string READ GetToneString;
      property ToneCandidateCount: integer read fToneCandidateCount;
      property ToneCandidates[Index: integer]: TToneCandidate read GetToneCandidate;
      property AudioFormat: TAudioFormatInfo READ fAudioFormat;
  end;

const
  DEFAULT_SOURCE_NAME = '[Default]';

type
  TAudioInputSource = record
    Name: UTF8String;
  end;

  // soundcard input-devices information
  TAudioInputDevice = class
    protected
      procedure ResetCaptureAnalysis;
      procedure CheckCapture(Now: System.QWord); virtual;
    public
      CfgIndex:      integer;   // index of this device in Ini.InputDeviceConfig
      Name:          UTF8String;    // soundcard name
      CaptureSerial: UTF8String;    // display only, never a config key
      Source:        array of TAudioInputSource; // soundcard input-sources
      SourceRestore: integer;  // source-index that will be selected after capturing (-1: not detected)
      MicSource:     integer;  // source-index of mic (-1: none detected)

      AudioFormat:     TAudioFormatInfo; // capture format info (e.g. 44.1kHz SInt16 stereo)
      CaptureChannel:  array of TCaptureBuffer; // sound-buffer references used for mono or stereo channel's capture data

      destructor Destroy; override;

      procedure LinkCaptureBuffer(ChannelIndex: integer; Sound: TCaptureBuffer);

      // TODO: add Open/Close functions so Start/Stop becomes faster
      //function Open():    boolean; virtual; abstract;
      //function Close():   boolean; virtual; abstract;
      function Start():   boolean; virtual; abstract;
      function Stop():    boolean; virtual; abstract;

      function GetVolume(): single;        virtual; abstract;
      procedure SetVolume(Volume: single); virtual; abstract;
  end;

  TBooleanDynArray = array of boolean;

  TAudioInputProcessor = class
    public
      Sound:  array of TCaptureBuffer; // sound-buffers for every player
      DeviceList: array of TAudioInputDevice;

      constructor Create;
      destructor Destroy; override;

      procedure UpdateInputDeviceConfig;

      {**
       * Validates the mic settings.
       * If a player was assigned to multiple mics a popup will be displayed
       * with the ID of the player.
       * The return value is the player number of the first player that is not
       * configured correctly or 0 if all players are correct.
       *}
      function ValidateSettings: integer;

      {**
       * Checks if players 1 to PlayerCount are configured correctly.
       * A player is configured if a device's channel is assigned to him.
       * For each player (up to PlayerCount) the state will be in PlayerState.
       * If a player's state is true the player is configured, otherwise not.
       * The return value is the player number of the first player that is not
       * configured correctly or 0 if all players are correct.
       * The PlayerState array is zero based (index 0 for player 1).
       *}
      function CheckPlayersConfig(PlayerCount: cardinal;
          var PlayerState: TBooleanDynArray): integer; overload;

      {**
       * Same as the array version but it does not output a state for each player.
       *}
      function CheckPlayersConfig(PlayerCount: cardinal): integer; overload;
      function ConfiguredPlayerCount(LocalCount: integer; out Slots: cardinal): integer;

      {**
       * Handle microphone input
       *}
      procedure HandleMicrophoneData(Buffer: PByteArray; Size: integer;
                                     InputDevice: TAudioInputDevice);
  end;

  TAudioInputBase = class( TInterfacedObject, IAudioInput )
    private
      Started: boolean;
      Monitoring: boolean;
    protected
      ScanMode: TAudioInputScanMode;
      SeenDeviceNames: array of UTF8String;

      procedure PrepareDeviceScan(AScanMode: TAudioInputScanMode);
      function IsDeviceAssigned(const name: UTF8String): boolean;
      function ShouldProbeDevice(const name: UTF8String): boolean;
      function UnifyDeviceName(const name: UTF8String; deviceIndex: integer): UTF8String;
    public
      function GetName: String;           virtual; abstract;
      function InitializeRecord(ScanMode: TAudioInputScanMode): boolean; virtual; abstract;
      function FinalizeRecord: boolean;   virtual;

      function IsCapturing: boolean;
      procedure CaptureStart(PlayerCount: integer = -1; MonitorOnly: boolean = false; LocalLimit: integer = -1);
      procedure CaptureStop(MonitorOnly: boolean = false);
  end;

  TSmallIntArray = array [0..(MaxInt div SizeOf(SmallInt))-1] of SmallInt;
  PSmallIntArray = ^TSmallIntArray;

  function AudioInputProcessor(): TAudioInputProcessor;
  function ToneAbsToString(const ToneAbs: integer): string;
  procedure UpdatePhoneAudio(CalibrationAllowed: boolean = false);
  procedure LogAudioInputDiagnostics;
  procedure CheckLocalCaptureDevices;

implementation

uses
  ULog,
  UPhoneAudio,
  URemoteBridgeIPC,
  URemoteInput,
  UTime,
  UNote;

var
  singleton_AudioInputProcessor : TAudioInputProcessor = nil;
  PhoneInputWasLive: array[0..UIni.IMaxPlayerCount-1] of boolean;
  PhoneInputLastSamples: array[0..UIni.IMaxPlayerCount-1] of QWord;
  PhoneCalibrationBuffers: array[0..UIni.IMaxPlayerCount-1] of TCaptureBuffer;
  LastAudioDiagnostics: QWord = 0;
  NextCaptureCheck: QWord = 0;

procedure CheckLocalCaptureDevices;
var
  Device: TAudioInputDevice;
  Now: QWord;
begin
  if not Assigned(singleton_AudioInputProcessor) then Exit;
  Now := GetTickCount64;
  if Now < NextCaptureCheck then Exit;
  NextCaptureCheck := Now + 250;
  for Device in singleton_AudioInputProcessor.DeviceList do
    Device.CheckCapture(Now);
end;

procedure LogAudioInputDiagnostics;
var I: integer;
    Capture: TCaptureBuffer;
    WindowMs: double;
begin
  if GetEnvironmentVariable('USCE_AUDIO_DIAGNOSTICS') <> '1' then Exit;
  if GetTickCount64 - LastAudioDiagnostics < 1000 then Exit;
  LastAudioDiagnostics := GetTickCount64;
  for I := 0 to High(AudioInputProcessor.Sound) do
  begin
    Capture := AudioInputProcessor.Sound[I];
    if (Capture.AudioFormat = nil) or (Capture.LastInputTicks = 0) then Continue;
    WindowMs := Capture.AnalysisBufferSize * 1000 / Capture.AudioFormat.SampleRate;
    Log.LogStatus(Format('player=%d rate=%.0f blockMs=%.2f windowMs=%.2f inputAgeMs=%d analysisUs=%.1f tone=%s',
      [I + 1, Capture.AudioFormat.SampleRate, Capture.LastInputBlockMs, WindowMs,
      GetTickCount64 - Capture.LastInputTicks, Capture.LastAnalysisMicroseconds, Capture.ToneString]), 'Audio timing');
  end;
  if PhoneAudio.Enabled then
    for I := 0 to Min(11, High(AudioInputProcessor.Sound)) do
      if RemoteInputProcessor.HasAssignedPlayer(I) then
        Log.LogStatus('slot=' + IntToStr(I+1) + ' ' + string(PhoneAudio.Status(I)), 'Native audio timing');
end;

procedure UpdatePhoneAudio(CalibrationAllowed: boolean);
var Samples: array[0..9599] of smallint;
    Count, I: integer;
    Generation: LongWord;
    Capture: TCaptureBuffer;
    Message, Owner: UTF8String;
    NowUs: int64;
    NeedsAnalysis: boolean;
begin
  if not PhoneAudio.Enabled then Exit;
  for I := 0 to High(AudioInputProcessor.Sound) do
  begin
    Capture := AudioInputProcessor.Sound[I];
    Count := PhoneAudio.Poll(@Samples[0], Length(Samples), I, Generation);
    Owner := RemoteInputProcessor.AssignedPlayerId(I);
    if RemoteInputProcessor.HasAssignedPlayer(I) or (Count > 0) then
      Capture.SubmitPhonePcm(nil, 0);
    if Count > 0 then
    begin
      if (Capture.PhoneCaptureGeneration <> 0) and (Generation <> 0) and
        (Capture.PhoneCaptureGeneration <> Generation) then
        Capture.Clear;
      Capture.SubmitPhonePcm(@Samples[0], Count);
      Capture.PhoneCaptureGeneration := Generation;
      PhoneInputLastSamples[I] := GetTickCount64;
      PhoneInputWasLive[I] := true;
    end
    else if PhoneInputWasLive[I] and (GetTickCount64 - PhoneInputLastSamples[I] > 250) then
    begin
      Capture.Clear;
      PhoneInputWasLive[I] := false;
    end;
    NowUs := int64(GetTickCount64) * 1000;
    NeedsAnalysis := PhoneAudio.Calibration.Tick(I, Owner, CalibrationAllowed,
      PhoneInputWasLive[I], NowUs, Message);
    if Message <> '' then RemoteBridgeIPC.SendJsonMessage(string(Message));
    Count := PhoneAudio.PollCalibration(@Samples[0], Length(Samples), I);
    if not NeedsAnalysis then FreeAndNil(PhoneCalibrationBuffers[I]);
    if NeedsAnalysis and (Count > 0) then
    begin
      if PhoneCalibrationBuffers[I] = nil then PhoneCalibrationBuffers[I] := TCaptureBuffer.Create;
      PhoneCalibrationBuffers[I].AnalysisBufferSize := AudioInputProcessor.Sound[I].AnalysisBufferSize;
      PhoneCalibrationBuffers[I].PitchAlgorithm := AudioInputProcessor.Sound[I].PitchAlgorithm;
      PhoneCalibrationBuffers[I].SubmitPhonePcm(@Samples[0], Count);
      PhoneCalibrationBuffers[I].AnalyzeBuffer;
      PhoneAudio.Calibration.Observe(I, int64(GetTickCount64) * 1000,
        PhoneCalibrationBuffers[I].ToneAbs, PhoneCalibrationBuffers[I].ToneValid);
    end;
  end;
end;

{ Global }

function AudioInputProcessor(): TAudioInputProcessor;
begin
  if singleton_AudioInputProcessor = nil then
    singleton_AudioInputProcessor := TAudioInputProcessor.create();

  result := singleton_AudioInputProcessor;
end;

{ TAudioInputDevice }

procedure TAudioInputDevice.CheckCapture(Now: System.QWord);
begin
end;

procedure TAudioInputDevice.ResetCaptureAnalysis;
var
  Channel: TCaptureBuffer;
begin
  for Channel in CaptureChannel do
    if Assigned(Channel) then Channel.ResetAnalysis;
end;

destructor TAudioInputDevice.Destroy;
begin
  Stop();
  Source := nil;
  CaptureChannel := nil;
  FreeAndNil(AudioFormat);
  inherited Destroy;
end;

procedure TAudioInputDevice.LinkCaptureBuffer(ChannelIndex: integer; Sound: TCaptureBuffer);
var
  OldSound: TCaptureBuffer;
begin
  // check bounds
  if ((ChannelIndex < 0) or (ChannelIndex > High(CaptureChannel))) then
    Exit;

  // reset previously assigned (old) capture-buffer
  OldSound := CaptureChannel[ChannelIndex];
  if (OldSound <> nil) then
  begin
    OldSound.StopCapture();
  end;

  // set audio-format of new capture-buffer
  if (Sound <> nil) then
  begin
    Sound.StartCapture(AudioFormat);
  end;

  // replace old with new buffer (Note: Sound might be nil)
  CaptureChannel[ChannelIndex] := Sound;
end;

{ TSound }

constructor TCaptureBuffer.Create;
begin
  inherited;
  LogBuffer := TMemoryStream.Create;
  fAnalysisBufferLock := SDL_CreateMutex();
  SetLength(AnalysisBuffer, CaptureHistorySamples);
  AnalysisBufferSize := CaptureWindowSamples;
  PitchAlgorithm := PDA_CAMDF;
  if GetEnvironmentVariable('USCE_AUDIO_DETECTOR') = 'amdf' then PitchAlgorithm := PDA_AMDF;
  // Experimental comparison for physical and phone microphones alike.
  case StrToIntDef(GetEnvironmentVariable('USCE_AUDIO_WINDOW'), CaptureWindowSamples) of
    1024: AnalysisBufferSize := 1024;
    2048: AnalysisBufferSize := 2048;
  end;
  ResetToneDiagnostics;
end;

destructor TCaptureBuffer.Destroy;
begin
  FreeAndNil(LogBuffer);
  FreeAndNil(fVoiceStream);
  FreeAndNil(fAudioFormat);
  SDL_UnlockMutex(fAnalysisBufferLock);
  SDL_DestroyMutex(fAnalysisBufferLock);
  fAnalysisBufferLock:=nil;
  inherited;
end;

procedure TCaptureBuffer.LockAnalysisBuffer();
begin
  SDL_LockMutex(fAnalysisBufferLock);
end;

procedure TCaptureBuffer.UnlockAnalysisBuffer();
begin
  SDL_UnlockMutex(fAnalysisBufferLock);
end;

procedure TCaptureBuffer.ResetToneDiagnostics;
begin
  fToneCandidateCount := 0;
  FillChar(fToneCandidates, SizeOf(fToneCandidates), 0);
  RawToneValid := false;
  RawTone := -1;
  RawToneAbs := -1;
end;

function TCaptureBuffer.GetToneCandidate(Index: integer): TToneCandidate;
begin
  if (Index >= 0) and (Index < fToneCandidateCount) then
    Result := fToneCandidates[Index]
  else
  begin
    Result.ToneAbs := -1;
    Result.Confidence := 0;
    Result.Correlation := 0;
    Result.Frequency := 0;
  end;
end;

procedure TCaptureBuffer.Clear;
begin
  PhoneCaptureGeneration := 0;
  if assigned(LogBuffer) then
    LogBuffer.Clear;
  ResetAnalysis;
end;

procedure TCaptureBuffer.ResetAnalysis;
begin
  LockAnalysisBuffer();
  FLocalCaptureEndUs := 0;
  FLocalBlockUs := 0;
  FLocalSamples := 0;
  FillChar(AnalysisBuffer[0], Length(AnalysisBuffer) * SizeOf(SmallInt), 0);
  UnlockAnalysisBuffer();
  ResetToneDiagnostics;
end;

procedure TCaptureBuffer.ProcessNewBuffer(Buffer: PByteArray; BufferSize: integer; AllowRecording: boolean;
  AllowBoost: boolean; CaptureEndUs: int64);
var
  BlockUs, ExpectedEndUs: int64;
  BufferOffset, HistorySize, PreviousSize: integer;
  SampleCount:  integer;
begin
  LastInputTicks := GetTickCount64;
  if (AudioFormat <> nil) and (AudioFormat.SampleRate > 0) then
    LastInputBlockMs := BufferSize * 1000 / (SizeOf(smallint) * AudioFormat.SampleRate);
  if (AudioFormat = nil) or (AudioFormat.Format <> asfS16) then Exit;

  // process BufferArray
  BufferOffset := 0;

  SampleCount := BufferSize div SizeOf(SmallInt);
  if SampleCount = 0 then Exit;

  LockAnalysisBuffer();
  try
    if (CaptureEndUs > 0) and (AudioFormat.SampleRate > 0) then
    begin
      // Retain a complete window that straddles a callback boundary. Limit
      // growth to the maximum callback frame count representable by SDL.
      HistorySize := Min(SampleCount, High(Word)) + CaptureWindowSamples;
      PreviousSize := Length(AnalysisBuffer);
      if HistorySize > PreviousSize then
      begin
        SetLength(AnalysisBuffer, HistorySize);
        if FLocalSamples > 0 then
          Move(AnalysisBuffer[PreviousSize - FLocalSamples],
            AnalysisBuffer[HistorySize - FLocalSamples], FLocalSamples * SizeOf(smallint));
      end;

      BlockUs := Round(SampleCount * 1000000.0 / AudioFormat.SampleRate);
      FLocalBlockUs := BlockUs;
      ExpectedEndUs := FLocalCaptureEndUs + BlockUs;
      if (FLocalCaptureEndUs = 0) or (Abs(CaptureEndUs - ExpectedEndUs) > Max(30000, BlockUs)) then
        FLocalSamples := 0
      else
        CaptureEndUs := ExpectedEndUs + EnsureRange(CaptureEndUs - ExpectedEndUs, -1000, 1000);
      FLocalCaptureEndUs := CaptureEndUs;
      FLocalSamples := Min(FLocalSamples + SampleCount, Length(AnalysisBuffer));
    end;
    if SampleCount > Length(AnalysisBuffer) then
    begin
      BufferOffset := (SampleCount - Length(AnalysisBuffer)) * SizeOf(smallint);
      SampleCount := Length(AnalysisBuffer);
    end;
    // Keep enough history to retrieve a full window from before the last callback.
    if SampleCount < Length(AnalysisBuffer) then
      Move(AnalysisBuffer[SampleCount], AnalysisBuffer[0],
        (Length(AnalysisBuffer) - SampleCount) * SizeOf(SmallInt));

    // copy new samples to analysis buffer
    Move(Buffer[BufferOffset], AnalysisBuffer[Length(AnalysisBuffer)-SampleCount],
         SampleCount * SizeOf(SmallInt));

  finally
    UnlockAnalysisBuffer();
  end;

  // Keep unmodified PCM for pitch analysis. Apply the gain to audible and saved output.
  if AllowBoost and (Assigned(fVoiceStream) or ((Ini.SavePlayback = 1) and not MonitorOnly)) then
    BoostBuffer(Buffer, BufferSize);
  if Assigned(fVoiceStream) then fVoiceStream.WriteData(Buffer, BufferSize);

  // save capture-data to BufferLong if enabled
  if AllowRecording and (Ini.SavePlayback = 1) and not MonitorOnly then
  begin
    // this is just for debugging (approx 15MB per player for a 3min song!!!)
    // For an in-game replay-mode we need to compress data so we do not
    // waste that much memory. Maybe ogg-vorbis with voice-preset in fast-mode?
    // Or we could use a faster but not that efficient lossless compression.
    LogBuffer.Write(Buffer^, BufferSize);
  end;
end;

function TCaptureBuffer.AnalysisGain: integer;
begin
  Result := 1;
  if (FLocalCaptureEndUs > 0) and (Ini.MicBoost in [0..3]) then
    Result := 1 shl Ini.MicBoost;
end;

function TCaptureBuffer.HasLocalCapture: boolean;
begin
  LockAnalysisBuffer;
  try
    Result := FLocalCaptureEndUs > 0;
  finally
    UnlockAnalysisBuffer;
  end;
end;

procedure TCaptureBuffer.AnalyzeBuffer;
var Unused: int64;
begin
  AnalyzeBuffer(Unused);
end;

procedure TCaptureBuffer.AnalyzeBuffer(out WindowCenterUs: int64);
begin
  WindowCenterUs := 0;
  if (AnalysisBufferSize <> 512) and (AnalysisBufferSize <> 1024) and
    (AnalysisBufferSize <> 2048) and (AnalysisBufferSize <> CaptureWindowSamples) then
    AnalysisBufferSize := CaptureWindowSamples;
  LockAnalysisBuffer;
  try
    if Assigned(AudioFormat) then
    begin
      if (FLocalSamples >= AnalysisBufferSize) and (AudioFormat.SampleRate > 0) then
        WindowCenterUs := FLocalCaptureEndUs - Round(AnalysisBufferSize * 500000.0 / AudioFormat.SampleRate);
      AnalyzeSamples(AnalysisBuffer, AnalysisBufferSize, AudioFormat.SampleRate, AnalysisGain);
    end
    else
      AnalyzeSamples(AnalysisBuffer, AnalysisBufferSize, 0);
  finally
    UnlockAnalysisBuffer;
  end;
end;

function TCaptureBuffer.AnalyzeLocalWindow(CenterUs: int64; Count: integer; out WaitUntilUs: int64): boolean;
var
  Window: array[0..4095] of smallint;
  Rate: double;
  EndIndex, Gain: integer;
begin
  Result := false;
  WaitUntilUs := 0;
  LockAnalysisBuffer;
  try
    if (AudioFormat = nil) or (FLocalCaptureEndUs = 0) then Exit;
    Rate := AudioFormat.SampleRate;
    if (Rate <= 0) or (Count < 1) or (Count > Length(Window)) then Exit;
    EndIndex := Length(AnalysisBuffer) - Round((FLocalCaptureEndUs - CenterUs) * Rate / 1000000.0) + Count div 2;
    if EndIndex - Count < Length(AnalysisBuffer) - FLocalSamples then Exit;
    if EndIndex > Length(AnalysisBuffer) then
    begin
      // The window's end can fall just after a callback and wait a full
      // block for the next one. Allow 10 ms extra for callback scheduling.
      WaitUntilUs := CenterUs + Max(int64(90000), FLocalBlockUs + Ceil((Count div 2) * 1000000.0 / Rate) + 10000);
      Exit;
    end;
    Move(AnalysisBuffer[EndIndex - Count], Window[Length(Window) - Count], Count * SizeOf(smallint));
    Gain := AnalysisGain;
  finally
    UnlockAnalysisBuffer;
  end;
  AnalyzeSamples(Window, Count, Rate, Gain);
  Result := true;
end;

procedure TCaptureBuffer.AnalyzeSamples(const Samples: array of smallint; Count: integer; SampleRate: double;
  Gain: integer; MeasureBoost: boolean);
var
  StartedCounter: UInt64;
  MaxSample, SampleIndex: integer;
  MaxVolume, Threshold: single;

  function ProbeHasPeriodicSignal: boolean;
  var
    Lag, I, Magnitude, Difference: integer;
  begin
    Lag := Delays[ToneAbs];
    if (Lag <= 0) or (Lag >= Count) then Exit(false);
    Magnitude := 0;
    Difference := 0;
    for I := Length(Samples) - Count + Lag to High(Samples) do
    begin
      Inc(Magnitude, Abs(integer(Samples[I])) + Abs(integer(Samples[I - Lag])));
      Inc(Difference, Abs(integer(Samples[I]) - integer(Samples[I - Lag])));
    end;
    Result := (Magnitude > 0) and (Difference * 3 < Magnitude);
  end;
begin
  StartedCounter := SDL_GetPerformanceCounter;
  ToneValid := false;
  ToneAbs := -1;
  Tone := -1;
  ResetToneDiagnostics;
  PhoneBoostProbeTone := -1;
  PhoneAboveHalfMeter := false;

  if SampleRate > 0 then
  begin
    MaxSample := 0;
    for SampleIndex := Length(Samples) - Count to High(Samples) do
      MaxSample := Max(MaxSample, Abs(integer(Samples[SampleIndex])));
    MaxVolume := MaxSample * Gain / -Low(SmallInt);
    Threshold := IThresholdVals[Ini.ThresholdIndex];
    if MeasureBoost then
      PhoneAboveHalfMeter := MaxVolume > 0.5;
    if MaxVolume >= Threshold then
      ToneValid := AnalyzePitch(PitchAlgorithm, Samples, Count, SampleRate)
    else if MeasureBoost and (MaxVolume < 0.5) and (MaxVolume * 2 >= Threshold) then
    begin
      // Doubling this window would clear the threshold without clipping.
      // Probe for a pitch while keeping the actual scoring result invalid.
      if AnalyzePitch(PitchAlgorithm, Samples, Count, SampleRate) and ProbeHasPeriodicSignal then
        PhoneBoostProbeTone := Tone;
      Tone := -1;
      ToneAbs := -1;
      ResetToneDiagnostics;
    end;
  end;

  LastAnalysisMicroseconds := (SDL_GetPerformanceCounter - StartedCounter) * 1000000.0 / SDL_GetPerformanceFrequency;
end;

function TCaptureBuffer.AnalyzePhoneWindow(PlayerIndex: integer; CenterHostUs: Int64; WindowSamples: integer;
  MeasureBoost: boolean): boolean;
var Window: array[0..4095] of SmallInt;
    Count: integer;
    function ReadWindow: boolean;
    begin
      Result := PhoneAudio.ReadCaptureWindow(PlayerIndex,
        CenterHostUs + Round(Count * 500000.0 / PhonePcmSampleRate),
        @Window[Length(Window) - Count], Count);
    end;
begin
  Result := false;
  Count := WindowSamples;
  if Count = 0 then Count := AnalysisBufferSize;
  if (Count < 1) or (Count > Length(Window)) then Exit;
  if not ReadWindow then
  begin
    // Use a shorter contiguous window when the usual window crosses a hole.
    if Count <> Length(Window) then Exit;
    Count := Length(Window) div 2;
    if not ReadWindow then Exit;
  end;
  AnalyzeSamples(Window, Count, PhonePcmSampleRate, 1, MeasureBoost);
  Result := true;
end;

procedure TCaptureBuffer.SubmitPhonePcm(Samples: pointer; Count: integer);
begin
  if (Count < 0) or (Count > 9600) or ((Count > 0) and (Samples = nil)) then Exit;
  if (fAudioFormat = nil) or (fAudioFormat.SampleRate <> 48000) or
    (fAudioFormat.Format <> asfS16) then
  begin
    StopCapture;
    FreeAndNil(fAudioFormat);
    fAudioFormat := TAudioFormatInfo.Create(1, 48000, asfS16);
    Clear;
  end;
  // Browser input already has its own gain controls. Do not inherit the global
  // physical-microphone boost, which can severely clip phone PCM.
  // No voice passthrough: avoid playing a delayed phone mic through speakers.
  FreeAndNil(fVoiceStream);
  if Count > 0 then ProcessNewBuffer(PByteArray(Samples), Count * SizeOf(smallint), false, false);
end;

function TCaptureBuffer.ArrayIndexOfMinimum(const AValues: array of real): Integer;
var
  LValIdx: Integer;
  LMinIdx: Integer = 0;
begin
  if Length(AValues) = 0 then Exit(-1);

  for LValIdx := 1 to High(AValues) do
    if AValues[LValIdx] <= AValues[LMinIdx] then
      LMinIdx := LValIdx;

  Result := LMinIdx;
end;

procedure TCaptureBuffer.UpdateToneCandidatesSimple(const Correlation: TCorrelationArray);
const
  WeightEpsilon = 1.0e-9;
var
  Weights: array[0..NumHalftones-1] of double;
  idx: integer;
  candidateIdx: integer;
  bestIdx: integer;
  totalWeight: double;
begin
  fToneCandidateCount := 0;
  FillChar(fToneCandidates, SizeOf(fToneCandidates), 0);

  for idx := 0 to NumHalftones-1 do
  begin
    if Correlation[idx] > 0 then
      Weights[idx] := 1.0 / (Correlation[idx] + WeightEpsilon)
    else if Correlation[idx] < 0 then
      Weights[idx] := 1.0 / (Abs(Correlation[idx]) + WeightEpsilon)
    else
      Weights[idx] := 0;
  end;

  for candidateIdx := 0 to MaxToneCandidates-1 do
  begin
    bestIdx := -1;
    for idx := 0 to NumHalftones-1 do
    begin
      if Weights[idx] <= 0 then
        Continue;
      if (bestIdx = -1) or (Weights[idx] > Weights[bestIdx]) then
        bestIdx := idx;
    end;
    if bestIdx < 0 then
      Break;

    fToneCandidates[fToneCandidateCount].ToneAbs := bestIdx;
    fToneCandidates[fToneCandidateCount].Frequency := Frequencies[bestIdx];
    fToneCandidates[fToneCandidateCount].Correlation := Correlation[bestIdx];
    fToneCandidates[fToneCandidateCount].Confidence := Weights[bestIdx];
    Weights[bestIdx] := -1;
    Inc(fToneCandidateCount);
  end;

  if (fToneCandidateCount = 0) and (ToneAbs >= 0) then
  begin
    fToneCandidates[0].ToneAbs := ToneAbs;
    fToneCandidates[0].Frequency := Frequencies[ToneAbs];
    fToneCandidates[0].Correlation := 0;
    fToneCandidates[0].Confidence := 1;
    fToneCandidateCount := 1;
  end;

  totalWeight := 0;
  for idx := 0 to fToneCandidateCount-1 do
    totalWeight := totalWeight + fToneCandidates[idx].Confidence;
  if (totalWeight > 0) and (fToneCandidateCount > 0) then
    for idx := 0 to fToneCandidateCount-1 do
      fToneCandidates[idx].Confidence := fToneCandidates[idx].Confidence / totalWeight;
end;

procedure TCaptureBuffer.SetFrequenciesAndDelays(SampleRate: double);
var
  ToneIndex:   integer;
begin
  for ToneIndex := 0 to NumHalftones-1 do
  begin
    // Freq(ToneIndex) = 440 Hz * 2^((ToneIndex-33)/12) --> Freq(ToneIndex=0) = 65.4064 Hz = C2
    Frequencies[ToneIndex] := BaseToneFreq * Power(2, (ToneIndex-33)/12);
    Delays[ToneIndex] := Round(SampleRate/Frequencies[ToneIndex]);
  end;
end;

function TCaptureBuffer.AnalyzePitch(PDA: TPDAType; const Samples: array of smallint; Count: integer; SampleRate: double): boolean;
var
  Correlation: TCorrelationArray;
begin
  // prepare to analyze
  SetFrequenciesAndDelays(SampleRate);

  // analyze halftones
  // Note: at the lowest tone (~65 Hz) and a buffer-size of 4096
  // at 44.1 (or 48 kHz) only 6 (or 5) samples are compared, this might be
  // too few samples -> use a bigger buffer-size
  case PDA of
    PDA_AMDF:
      begin
        Correlation := AverageMagnitudeDifference(Samples, Count);
        ToneAbs := ArrayIndexOfMinimum(Correlation);
      end;
    PDA_CAMDF:
      begin
        Correlation := CircularAverageMagnitudeDifference(Samples, Count);
        ToneAbs := ArrayIndexOfMinimum(Correlation);
      end;
  end;

  if ToneAbs < 0 then
  begin
    RawToneValid := false;
    RawTone := -1;
    RawToneAbs := -1;
    UpdateToneCandidatesSimple(Correlation);
    Result := false;
    Exit;
  end;

  Tone := ToneAbs mod 12;
  RawToneValid := true;
  RawTone := Tone;
  RawToneAbs := ToneAbs;
  UpdateToneCandidatesSimple(Correlation);
  Result := true;
end;

// Average Magnitude Difference Function (AMDF) is defined as
//   D(\tau)=\frac{1}{N-\tau-1}\sum_{n=0}^{N-\tau-1}|x(n) - x(n+\tau)|
// where \tau = Delay, n = SampleIndex, N = AnalysisBufferSize, x = AnalysisBuffer
// See: Equation (1) in http://www.utdallas.edu/~hxb076000/citing_papers/Muhammad%20Extended%20Average%20Magnitude%20Difference.pdf
function TCaptureBuffer.AverageMagnitudeDifference(const Samples: array of smallint; Count: integer): TCorrelationArray;
var
  ToneIndex:   integer;
  Correlation: TCorrelationArray;
  SampleIndex: integer; // index of sample to analyze
begin
  // accumulate the magnitude differences for samples in Samples
  for ToneIndex := 0 to NumHalftones-1 do
    begin
      Correlation[ToneIndex] := 0;
      for SampleIndex := 0 to (Count-Delays[ToneIndex]-1) do
      begin
        Correlation[ToneIndex] := Correlation[ToneIndex] + Abs(
          Samples[Length(Samples)-Count+SampleIndex] -
          Samples[Length(Samples)-Count+SampleIndex+Delays[ToneIndex]]);
      end;
      if Count > Delays[ToneIndex] then
        Correlation[ToneIndex] := Correlation[ToneIndex] / (Count-Delays[ToneIndex])
      else
        Correlation[ToneIndex] := MaxDouble;
    end;

  // return average magnitude difference
  Result := Correlation;
end;


// Circular Average Magnitude Difference Function (CAMDF) is defined as
//   D_C(\tau)=\sum_{n=0}^{N-1}|x(mod(n+\tau, N)) - x(n)|
// where \tau = Delay, n = SampleIndex, N = Count, x = Samples
// See: Equation (4) in http://www.utdallas.edu/~hxb076000/citing_papers/Muhammad%20Extended%20Average%20Magnitude%20Difference.pdf
function TCaptureBuffer.CircularAverageMagnitudeDifference(const Samples: array of smallint; Count: integer): TCorrelationArray;
var
  ToneIndex:   integer;
  Correlation: TCorrelationArray;
  SampleIndex: integer; // index of sample to analyze
begin
  // accumulate the magnitude differences for samples in Samples
  for ToneIndex := 0 to NumHalftones-1 do
  begin
    Correlation[ToneIndex] := 0;
    for SampleIndex := 0 to (Count-1) do
    begin
      // Suggestion for calculation efficiency improvement from deuteragenie:
      // Replacing 'i mod buffersize' by 'i & (buffersize-1)' when i is positive and buffersize is a power of two should speed the modulo compuation by 5x-10x
      //Correlation[ToneIndex] += Abs(Samples[(SampleIndex+Delays[ToneIndex]) mod Count] - Samples[SampleIndex]);
      Correlation[ToneIndex] := Correlation[ToneIndex] + Abs(
        Samples[Length(Samples)-Count+((SampleIndex+Delays[ToneIndex]) and (Count-1))] -
        Samples[Length(Samples)-Count+SampleIndex]);
    end;
    Correlation[ToneIndex] := Correlation[ToneIndex] / Count;
  end;

  // return circular average magnitude difference
  Result := Correlation;
end;

function TCaptureBuffer.MaxSampleVolume: single;
var Clipped: boolean;
begin
  Result := MaxSampleVolume(Clipped);
end;

function TCaptureBuffer.MaxSampleVolume(out Clipped: boolean): single;
var
  lSampleIndex: integer;
  Sample, MaxVolume: integer;
begin
  Clipped := false;
  MaxVolume := 0;
  LockAnalysisBuffer();
  try
    for lSampleIndex := Length(AnalysisBuffer) - CaptureWindowSamples to High(AnalysisBuffer) do
    begin
      Sample := AnalysisBuffer[lSampleIndex];
      if (Sample = Low(SmallInt)) or (Sample = High(SmallInt)) then
        Clipped := true;
      if Abs(Sample) > MaxVolume then
        MaxVolume := Abs(Sample);
    end;
    MaxVolume := MaxVolume * AnalysisGain;
  finally
    UnlockAnalysisBuffer();
  end;

  Clipped := Clipped or (MaxVolume > High(SmallInt));
  Result := Min(1.0, MaxVolume / -Low(SmallInt));
end;

const
  ToneStrings: array[0..11] of string = (
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  );

function ToneAbsToString(const ToneAbs: integer): string;
begin
  if ToneAbs < 0 then
    Exit('-');
  Result := ToneStrings[ToneAbs mod 12] + IntToStr(ToneAbs div 12 + ToneStringOctaveOffset);
end;

function TCaptureBuffer.GetToneString: string;
begin
  if (ToneValid) then
    Result := ToneAbsToString(ToneAbs)
  else
    Result := '-';
end;

procedure TCaptureBuffer.BoostBuffer(Buffer: PByteArray; Size: integer);
var
  i:            integer;
  Value:        longint;
  SampleCount:  integer;
  SampleBuffer: PSmallIntArray; // buffer handled as array of samples
  Boost:        byte;
begin
  // TODO: set boost per device
  case Ini.MicBoost of
    0:   Boost := 1;
    1:   Boost := 2;
    2:   Boost := 4;
    3:   Boost := 8;
    else Boost := 1;
  end;

  // at the moment we will boost SInt16 data only
  if (AudioFormat.Format = asfS16) then
  begin
    // interpret buffer as buffer of bytes
    SampleBuffer := PSmallIntArray(Buffer);
    SampleCount := Size div AudioFormat.FrameSize;

    // boost buffer
    for i := 0 to SampleCount-1 do
    begin
      Value := SampleBuffer^[i] * Boost;

      if Value > High(Smallint) then
        Value := High(Smallint);

      if Value < Low(Smallint) then
        Value := Low(Smallint);

      SampleBuffer^[i] := Value;
    end;
  end;
end;

procedure TCaptureBuffer.StartCapture(Format: TAudioFormatInfo);
begin
  // free old audio-format info
  FreeAndNil(fAudioFormat);
  // copy the new input-device audio-format ...
  fAudioFormat := Format.Copy;
  // and adjust it because capture buffers are always mono
  fAudioFormat.Channels := 1;

  if (Ini.VoicePassthrough = 1) and not MonitorOnly then
  begin
    // TODO: map odd players to the left and even players to the right speaker
    fVoiceStream := AudioPlayback.CreateVoiceStream(CHANNELMAP_FRONT, fAudioFormat);
  end;
end;

procedure TCaptureBuffer.StopCapture();
begin
  FreeAndNil(fVoiceStream);
end;

{ TAudioInputProcessor }

constructor TAudioInputProcessor.Create;
var
  i: integer;
begin
  inherited;
  SetLength(Sound, UIni.IMaxPlayerCount);
  for i := 0 to High(Sound) do
    Sound[i] := TCaptureBuffer.Create;
end;

destructor TAudioInputProcessor.Destroy;
var
  i: integer;
begin
  for i := 0 to High(Sound) do
  begin
    Sound[i].Free;
    FreeAndNil(PhoneCalibrationBuffers[i]);
  end;
  SetLength(Sound, 0);
  inherited;
end;

// updates InputDeviceConfig with current input-device information
// See: TIni.LoadInputDeviceCfg()
procedure TAudioInputProcessor.UpdateInputDeviceConfig;
var
  deviceIndex:    integer;
  newDevice:      boolean;
  deviceIniIndex: integer;
  deviceCfg:      PInputDeviceConfig;
  device:         TAudioInputDevice;
  channelCount:   integer;
  channelIndex:   integer;
  i:              integer;
begin
  // Input devices - append detected soundcards
  for deviceIndex := 0 to High(DeviceList) do
  begin
    newDevice := true;
    //Search for Card in List
    for deviceIniIndex := 0 to High(Ini.InputDeviceConfig) do
    begin
      deviceCfg := @Ini.InputDeviceConfig[deviceIniIndex];
      device := DeviceList[deviceIndex];

      if (deviceCfg.Name = Trim(device.Name)) then
      begin
        newDevice := false;

        // store highest channel index as an offset for the new channels
        channelIndex := High(deviceCfg.ChannelToPlayerMap);
        // add missing channels or remove non-existing ones
        SetLength(deviceCfg.ChannelToPlayerMap, device.AudioFormat.Channels);
        // assign added channels to no player
        for i := channelIndex+1 to High(deviceCfg.ChannelToPlayerMap) do
        begin
          deviceCfg.ChannelToPlayerMap[i] := CHANNEL_OFF;
        end;

        // associate ini-index with device
        device.CfgIndex := deviceIniIndex;
        break;
      end;
    end;

    //If not in List -> Add
    if newDevice then
    begin
      // resize list
      SetLength(Ini.InputDeviceConfig, Length(Ini.InputDeviceConfig)+1);
      deviceCfg := @Ini.InputDeviceConfig[High(Ini.InputDeviceConfig)];
      device := DeviceList[deviceIndex];

      // associate ini-index with device
      device.CfgIndex := High(Ini.InputDeviceConfig);

      deviceCfg.Name := Trim(device.Name);
      deviceCfg.Input := 0;
      deviceCfg.Latency := LATENCY_AUTODETECT;

      channelCount := device.AudioFormat.Channels;
      SetLength(deviceCfg.ChannelToPlayerMap, channelCount);

      for channelIndex := 0 to channelCount-1 do
      begin
        // Do not set any default on first start of USDX.
        // Otherwise most probably the wrong device (internal sound card)
        // will be selected.
        // It is better to force the user to configure the mics himself.
        deviceCfg.ChannelToPlayerMap[channelIndex] := CHANNEL_OFF;
      end;
    end;
  end;
end;

function TAudioInputProcessor.ValidateSettings: integer;
var
  I, J: integer;
  PlayerID: integer;
  MaxPlayerID: integer;
  PlayerMap: array [0 .. UIni.IMaxPlayerCount - 1] of boolean;
  InputDevice: TAudioInputDevice;
  InputDeviceCfg: PInputDeviceConfig;
begin
  MaxPlayerID := Length(PlayerMap);

  // mark all players as unassigned
  for I := 0 to High(PlayerMap) do
    PlayerMap[I] := false;

  // iterate over all active devices
  for I := 0 to High(DeviceList) do
  begin
    InputDevice := DeviceList[I];
    InputDeviceCfg := @Ini.InputDeviceConfig[InputDevice.CfgIndex];
    // iterate over all channels of the current devices
    for J := 0 to High(InputDeviceCfg.ChannelToPlayerMap) do
    begin
      // get player that was mapped to the current device channel
      PlayerID := InputDeviceCfg.ChannelToPlayerMap[J];
      if (PlayerID <> CHANNEL_OFF) then
      begin
        // avoid out-of-bounds access when switching between game versions with different max player counts
        if (PlayerID < 1) or (PlayerID > MaxPlayerID) then
          continue;

        // check if player is already assigned to another device/channel
        if (PlayerMap[PlayerID - 1]) then
        begin
          Result := PlayerID;
          Exit;
        end;

        // mark player as assigned to a device
        PlayerMap[PlayerID - 1] := true;
      end;
    end;
  end;
  Result := 0;
end;

function TAudioInputProcessor.CheckPlayersConfig(PlayerCount: cardinal;
  var PlayerState: TBooleanDynArray): integer;
var
  DeviceIndex:  integer;
  ChannelIndex: integer;
  Device:       TAudioInputDevice;
  DeviceCfg:    PInputDeviceConfig;
  PlayerIndex:  integer;
  I: integer;
begin
  SetLength(PlayerState, PlayerCount);
  // set all entries to "not configured"
  for I := 0 to High(PlayerState) do
  begin
    PlayerState[I] := false;
  end;

  // check each used device
  for DeviceIndex := 0 to High(AudioInputProcessor.DeviceList) do
  begin
    Device := AudioInputProcessor.DeviceList[DeviceIndex];
    if not assigned(Device) then
      continue;
    DeviceCfg := @Ini.InputDeviceConfig[Device.CfgIndex];

    // check if device is used
    for ChannelIndex := 0 to High(DeviceCfg.ChannelToPlayerMap) do
    begin
      PlayerIndex := DeviceCfg.ChannelToPlayerMap[ChannelIndex] - 1;
      if (PlayerIndex >= 0) and (PlayerIndex < PlayerCount) then
        PlayerState[PlayerIndex] := true;
    end;
  end;

  Result := 0;
  for I := 0 to High(PlayerState) do
  begin
    if (PlayerState[I] = false) then
    begin
      Result := I + 1;
      Break;
    end;
  end;
end;

function TAudioInputProcessor.CheckPlayersConfig(PlayerCount: cardinal): integer;
var
  PlayerState: TBooleanDynArray;
begin
  Result := CheckPlayersConfig(PlayerCount, PlayerState);
end;

function TAudioInputProcessor.ConfiguredPlayerCount(LocalCount: integer; out Slots: cardinal): integer;
var Local: TBooleanDynArray; I: integer;
begin
  CheckPlayersConfig(UIni.IMaxPlayerCount, Local);
  Slots := 0;
  Result := 0;
  for I := 0 to High(Local) do
    if ((I < LocalCount) and Local[I]) or RemoteInputProcessor.HasAssignedPlayer(I) then
    begin
      Slots := Slots or (cardinal(1) shl I);
      Result := I + 1;
    end;
end;

{*
 * Handles captured microphone input data.
 * Params:
 *   Buffer - buffer of signed 16bit interleaved stereo PCM-samples.
 *     Interleaved means that a right-channel sample follows a left-
 *     channel sample and vice versa (0:left[0],1:right[0],2:left[1],...).
 *   Length - number of bytes in Buffer
 *   Input - Soundcard-Input used for capture
 *}
procedure TAudioInputProcessor.HandleMicrophoneData(Buffer: PByteArray; Size: integer; InputDevice: TAudioInputDevice);
var
  MultiChannelBuffer:      PByteArray;  // buffer handled as array of bytes (offset relative to channel)
  SingleChannelBuffer:     PByteArray;  // temporary buffer for new samples per channel
  SingleChannelBufferSize: integer;
  ChannelIndex:            integer;
  CaptureChannel:          TCaptureBuffer;
  AudioFormat:             TAudioFormatInfo;
  SampleSize:              integer;
  SamplesPerChannel:       integer;
  i:                       integer;
  SourcePtr:               PByte;
  DestPtr:                 PByte;
  CaptureEndUs:            int64;
begin
  CaptureEndUs := MonotonicMicroseconds;
  AudioFormat := InputDevice.AudioFormat;
  if (AudioFormat = nil) then
    Exit;

  SampleSize := AudioSampleSize[AudioFormat.Format];
  if (SampleSize <= 0) or (AudioFormat.FrameSize <= 0) then
    Exit;

  SamplesPerChannel := Size div AudioFormat.FrameSize;
  if (SamplesPerChannel <= 0) then
    Exit;

  SingleChannelBufferSize := SamplesPerChannel * SampleSize;
  if (SingleChannelBufferSize <= 0) then
    Exit;

  GetMem(SingleChannelBuffer, SingleChannelBufferSize);
  try
    // process channels
    for ChannelIndex := 0 to High(InputDevice.CaptureChannel) do
    begin
      CaptureChannel := InputDevice.CaptureChannel[ChannelIndex];
      // check if a capture buffer was assigned, otherwise there is nothing to do
      if CaptureChannel <> nil then
      begin
        // Use pointer arithmetic instead of open-array indexing to avoid range
        // checks on bogus channel layouts reported by some devices.
        MultiChannelBuffer := Buffer;
        SourcePtr := PByte(MultiChannelBuffer);
        Inc(SourcePtr, ChannelIndex * SampleSize);

        DestPtr := PByte(SingleChannelBuffer);

        // separate channel-data from interleaved multi-channel (e.g. stereo) data
        for i := 0 to SamplesPerChannel-1 do
        begin
          Move(SourcePtr^, DestPtr^, SampleSize);
          Inc(SourcePtr, AudioFormat.FrameSize);
          Inc(DestPtr, SampleSize);
        end;
        CaptureChannel.ProcessNewBuffer(SingleChannelBuffer, SingleChannelBufferSize, true, true, CaptureEndUs);
      end;
    end;
  finally
    FreeMem(SingleChannelBuffer);
  end;
end;

{ TAudioInputBase }

function TAudioInputBase.FinalizeRecord: boolean;
var
  i: integer;
begin
  for i := 0 to High(AudioInputProcessor.DeviceList) do
    AudioInputProcessor.DeviceList[i].Free();
  AudioInputProcessor.DeviceList := nil;
  SeenDeviceNames := nil;
  Result := true;
end;

procedure TAudioInputBase.PrepareDeviceScan(AScanMode: TAudioInputScanMode);
begin
  ScanMode := AScanMode;
  SeenDeviceNames := nil;
end;

function TAudioInputBase.IsDeviceAssigned(const name: UTF8String): boolean;
var
  DeviceIniIndex: integer;
  ChannelIndex: integer;
  DeviceCfg: PInputDeviceConfig;
begin
  Result := false;

  for DeviceIniIndex := 0 to High(Ini.InputDeviceConfig) do
  begin
    DeviceCfg := @Ini.InputDeviceConfig[DeviceIniIndex];
    if (DeviceCfg.Name <> Trim(name)) then
      continue;

    for ChannelIndex := 0 to High(DeviceCfg.ChannelToPlayerMap) do
    begin
      if (DeviceCfg.ChannelToPlayerMap[ChannelIndex] <> CHANNEL_OFF) then
      begin
        Result := true;
        Exit;
      end;
    end;

    Exit;
  end;
end;

function TAudioInputBase.ShouldProbeDevice(const name: UTF8String): boolean;
begin
  Result := (ScanMode = aimFull) or IsDeviceAssigned(name);
end;

{*
 * Start capturing on all used input-device.
 *}
function TAudioInputBase.IsCapturing: boolean;
begin
  Result := Started;
end;

procedure TAudioInputBase.CaptureStart(PlayerCount: integer; MonitorOnly: boolean; LocalLimit: integer);
var
  S:            integer;
  DeviceIndex:  integer;
  ChannelIndex: integer;
  Device:       TAudioInputDevice;
  DeviceCfg:    PInputDeviceConfig;
  DeviceUsed:   boolean;
  Player:       integer;
begin
  if (Started) then
    CaptureStop();

  if PlayerCount < 0 then PlayerCount := PlayersPlay;
  PlayerCount := EnsureRange(PlayerCount, 0, Length(AudioInputProcessor.Sound));

  // reset buffers
  for S := 0 to High(AudioInputProcessor.Sound) do
  begin
    AudioInputProcessor.Sound[S].Clear;
    AudioInputProcessor.Sound[S].MonitorOnly := MonitorOnly;
  end;

  // start capturing on each used device
  for DeviceIndex := 0 to High(AudioInputProcessor.DeviceList) do
  begin
    Device := AudioInputProcessor.DeviceList[DeviceIndex];
    if not assigned(Device) then
      continue;
    DeviceCfg := @Ini.InputDeviceConfig[Device.CfgIndex];

    DeviceUsed := false;

    // check if device is used
    for ChannelIndex := 0 to High(DeviceCfg.ChannelToPlayerMap) do
    begin
      Player := DeviceCfg.ChannelToPlayerMap[ChannelIndex] - 1;
      if (Player < 0) or (Player >= PlayerCount) or ((LocalLimit >= 0) and (Player >= LocalLimit)) then
      begin
        Device.LinkCaptureBuffer(ChannelIndex, nil);
      end
      else
      begin
        Device.LinkCaptureBuffer(ChannelIndex, AudioInputProcessor.Sound[Player]);
        DeviceUsed := true;
      end;
    end;

    // start device if used
    if (DeviceUsed) then
    begin
      //Log.BenchmarkStart(2);
      Device.Start();
      //Log.BenchmarkEnd(2);
      //Log.LogBenchmark('Device.Start', 2) ;
    end;
  end;

  Monitoring := MonitorOnly;
  Started := true;
end;

{*
 * Stop input-capturing on all soundcards.
 *}
procedure TAudioInputBase.CaptureStop(MonitorOnly: boolean);
var
  DeviceIndex:  integer;
  ChannelIndex: integer;
  Device:       TAudioInputDevice;
  DeviceCfg:    PInputDeviceConfig;
begin
  // A screen finishing its fade must not stop the next screen's song capture.
  if MonitorOnly and not Monitoring then Exit;
  for DeviceIndex := 0 to High(AudioInputProcessor.DeviceList) do
  begin
    Device := AudioInputProcessor.DeviceList[DeviceIndex];
    if not assigned(Device) then
      continue;

    Device.Stop();

    // disconnect capture buffers
    DeviceCfg := @Ini.InputDeviceConfig[Device.CfgIndex];
    for ChannelIndex := 0 to High(DeviceCfg.ChannelToPlayerMap) do
      Device.LinkCaptureBuffer(ChannelIndex, nil);
  end;

  Started := false;
  Monitoring := false;
end;

function TAudioInputBase.UnifyDeviceName(const name: UTF8String; deviceIndex: integer): UTF8String;
var
  count: integer; // count of devices with this name

  function IsDuplicate(const name: UTF8String): boolean;
  var
    i: integer;
  begin
    Result := false;
    // search already seen devices with same description
    for i := 0 to High(SeenDeviceNames) do
    begin
      if (SeenDeviceNames[i] = name) then
      begin
        Result := true;
        Break;
      end;
    end;
  end;

begin
  count := 1;
  result := name;

  // if there is another device with the same ID, search for an available name
  while (IsDuplicate(result)) do
  begin
    Inc(count);
    // set description
    result := name + ' ('+IntToStr(count)+')';
  end;

  SetLength(SeenDeviceNames, Length(SeenDeviceNames) + 1);
  SeenDeviceNames[High(SeenDeviceNames)] := result;
end;

end.
