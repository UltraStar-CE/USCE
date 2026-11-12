{* UltraStar Deluxe - MIDI Audio Source Stream
 *
 * Generates synthesized audio from MIDI events for playback via the standard audio interface.
 *}

unit MidiAudioSourceStream;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

uses
  Classes,
  SysUtils,
  UAudioPlaybackBase,
  Math,
  UMusic,
  ULog,
  SyncObjs;

type
  TPianoMode = record
    Previous, Current, Coefficient, Amplitude, Decay: Double;
  end;
  TPianoModes = array[0..47] of TPianoMode;
  TSynthEventKind = (sekNoteOn, sekNoteOff, sekClick, sekStopAll);

  TScheduledSynthEvent = record
    Time: Double;
    Kind: TSynthEventKind;
    Pitch: Byte;
    Velocity: Byte;
  end;

type
  TMidiAudioSourceStream = class(TAudioSourceStream)
  private
    FFormat: TAudioFormatInfo;
    FPosition: real;
    // Synthesizer state
    FActive: Boolean;
    FTone, FClickSound: Integer;
    FPianoModes, FPianoTailModes: TPianoModes;
    FPianoBody: array[0..3] of TPianoMode;
    FPianoContactTime: Double;
    FPianoTailLevel, FPianoTailAge: Double;
    FNote: Integer;
    FFreq: Double;
    FVel: Double;
    FPhase: Double;
    FRelease: Boolean;
    FEnvLevel: Double;
    FNoteAge: Double;
    FReleaseAge: Double;
    FReleaseLevel: Double;
    FClickActive: Boolean;
    FClickAge: Double;
    FClickVel: Double;
    FEvents: array of TScheduledSynthEvent;
    FLock: TCriticalSection;

    procedure QueueEvent(Time: Double; Kind: TSynthEventKind; Pitch: Byte; Velocity: Byte);
    procedure ProcessEvents(Time: Double);
    procedure ApplyNoteOn(Pitch: Byte; Velocity: Byte);
    procedure ApplyNoteOff(Pitch: Byte);
    procedure ApplyClick(Velocity: Byte);
    procedure ApplyStopAll;
  protected
    function IsEOF: boolean; override;
    function IsError: boolean; override;
    function GetLength: real; override;
    function GetPosition: real; override;
    procedure SetPosition(Time: real); override;
    function GetLoop(): boolean; override;
    procedure SetLoop(Enabled: boolean); override;
  public
    constructor Create(Format: TAudioFormatInfo);
    destructor Destroy; override;
    function ReadData(Buffer: PByte; BufferSize: integer): integer; override;
    function GetAudioFormatInfo: TAudioFormatInfo; override;
    procedure Close; override;
    procedure SetTone(Tone: Integer);
    procedure SetClickSound(Sound: Integer);
    procedure NoteOn(Pitch: Byte; Velocity: Byte = 127; Time: Double = -1.0);
    procedure NoteOff(Pitch: Byte; Time: Double = -1.0);
    procedure Click(Velocity: Byte = 127; Time: Double = -1.0);
    procedure StopAll(Time: Double = -1.0);
  end;

implementation

const
  OrganAttackTime = 0.001;
  OrganReleaseTime = 0.050;
  OrganGain = 0.62;
  OrganSilenceLevel = 0.0004;
  ClickDecayTime = 0.014;
  ClickSilenceLevel = 0.0005;
  ClickGain = 1.55;

function OrganEnvelope(Age: Double): Double;
begin
  if Age < OrganAttackTime then
    Result := Age / OrganAttackTime
  else
    Result := 1.0;
end;

function OrganWave(Phase, Age: Double): Double;
var
  Percussion: Double;
begin
  Percussion := Exp(-Age / 0.16);

  Result :=
    0.72 * Sin(Phase) +
    0.18 * Sin(2.0 * Phase) +
    0.10 * Sin(3.0 * Phase) +
    Percussion * (
      0.28 * Sin(4.0 * Phase) +
      0.14 * Sin(5.0 * Phase) +
      0.08 * Sin(6.0 * Phase)
    );
end;

// Modal struck-string model: a finite hammer-force pulse drives damped
// oscillators instead of starting a pre-shaped, plucked waveform.
procedure StartPianoModes(var Modes: TPianoModes; Frequency, Rate: Double);
var
  I, Partial, StringIndex: Integer;
  Stiffness, ModeFrequency, Step, Radius, Strike: Double;
begin
  Stiffness := EnsureRange(0.000025 * Power(Frequency / 440, 0.8), 0.00001, 0.0003);
  for I := 0 to High(Modes) do
  begin
    FillChar(Modes[I], SizeOf(Modes[I]), 0);
    Partial := I div 3 + 1;
    StringIndex := I mod 3;
    ModeFrequency := Frequency * Partial * Sqrt(1 + Stiffness * Partial * Partial) *
      (1 + (StringIndex - 1) * 0.0007);
    if ModeFrequency >= Rate / 2 then Continue;
    Step := 2 * Pi * ModeFrequency / Rate;
    Radius := Exp(-(0.30 + 0.22 * Sqrt(Frequency / 440) +
      0.018 * Power(Partial, 1.7) + StringIndex * 0.12) / Rate);
    // Force applied near one eighth of the string. The finite contact pulse
    // supplies the high-frequency rolloff, which changes with strike strength.
    Strike := Sin(Pi * Partial / 8.2);
    Modes[I].Coefficient := 2 * Radius * Cos(Step);
    Modes[I].Decay := Sqr(Radius);
    Modes[I].Amplitude := 1.8 * Sin(Step) * Strike / Sqrt(Partial) / 3;
  end;
end;

procedure StartPianoBody(var Modes: array of TPianoMode; Rate: Double);
const Frequencies: array[0..3] of Double = (180, 520, 1150, 2700);
var I: Integer; Step, Radius: Double;
begin
  for I := 0 to High(Modes) do
  begin
    FillChar(Modes[I], SizeOf(Modes[I]), 0);
    Step := 2 * Pi * Frequencies[I] / Rate;
    Radius := Exp(-(35 + I * 18) / Rate);
    Modes[I].Coefficient := 2 * Radius * Cos(Step);
    Modes[I].Decay := Sqr(Radius);
    Modes[I].Amplitude := 0.16 * Sin(Step);
  end;
end;

function PianoFrame(var Modes: array of TPianoMode; Force: Double): Double;
var I: Integer; Next: Double;
begin
  Result := 0;
  for I := 0 to High(Modes) do
    with Modes[I] do
    begin
      Next := Coefficient * Current - Decay * Previous + Amplitude * Force;
      Previous := Current;
      Current := Next;
      Result := Result + Current;
    end;
end;

function HammerForce(Age, ContactTime, Rate: Double): Double;
begin
  Result := 0;
  if (Age > 0) and (Age < ContactTime) then
    // Unit-area, smooth contact pulse; stronger strikes shorten contact time.
    Result := Power(Sin(Pi * Age / ContactTime), 3) *
      (3 * Pi / (4 * ContactTime * Rate));
end;

function ToneWave(Tone: Integer; Phase, Age, Frequency, SampleRate: Double): Double;
var N, Limit: Integer; Fundamental, Cosine, Previous, Current, Next: Double;
begin
  case Tone of
    1: begin
      Result := Sin(Phase);
      if 3 * Frequency < SampleRate / 2 then Result := Result - Sin(3 * Phase) / 9;
      if 5 * Frequency < SampleRate / 2 then Result := Result + Sin(5 * Phase) / 25;
      Result := Result * (8 / (Pi * Pi));
    end;
    2: Result := 0; // The piano uses its own oscillator state.
    3: Result := Sin(Phase);
    4, 5: begin
      // Band-limited Fourier series. Recurrence avoids a sine call per partial.
      Limit := Min(32, Trunc((SampleRate / 2 - 1) / Frequency));
      Fundamental := Sin(Phase);
      Cosine := 2 * Cos(Phase);
      Previous := 0;
      Current := Fundamental;
      Result := 0;
      for N := 1 to Limit do
      begin
        if (Tone = 5) or Odd(N) then Result := Result + Current / N;
        Next := Cosine * Current - Previous;
        Previous := Current;
        Current := Next;
      end;
      if Tone = 4 then Result := Result * (4 / Pi)
      else Result := Result * (2 / Pi);
    end;
    else Result := OrganWave(Phase, Age);
  end;
end;

procedure TMidiAudioSourceStream.SetTone(Tone: Integer);
begin
  FLock.Enter;
  try
    FTone := EnsureRange(Tone, 0, 5);
  finally
    FLock.Leave;
  end;
end;

procedure TMidiAudioSourceStream.SetClickSound(Sound: Integer);
begin
  FLock.Enter;
  try
    FClickSound := EnsureRange(Sound, 0, 1);
  finally
    FLock.Leave;
  end;
end;

function ClickNoise(Age: Double): Double;
var
  X: Double;
begin
  X := Sin((Age * 44100.0 + 0.137) * 15731.743) * 43758.5453;
  Result := 2.0 * Frac(Abs(X)) - 1.0;
end;

function ClickWave(Age: Double): Double;
var
  Stick: Double;
  Crack: Double;
  Edge: Double;
  Noise0: Double;
  Noise1: Double;
  Noise2: Double;
begin
  Noise0 := ClickNoise(Age);
  Noise1 := ClickNoise(Age + 0.00017);
  Noise2 := ClickNoise(Age + 0.00043);

  if Noise0 >= 0 then
    Edge := 1.0
  else
    Edge := -1.0;

  Stick := Edge * Exp(-Age / 0.00075);
  Crack := (Noise0 - 0.72 * Noise1 + 0.46 * Noise2) * Exp(-Age / 0.0045);

  Result := 1.10 * Stick + 1.35 * Tanh(2.6 * Crack);
end;

function SelectedClickWave(Sound: Integer; Age: Double): Double;
var Attack: Double;
begin
  // Preserve the original sound exactly, including its transient.
  if Sound = 0 then Exit(ClickWave(Age));
  Attack := Min(1.0, Age / 0.0003);
  Result := 0.32 * (ClickNoise(Age) - ClickNoise(Age + 1 / 44100)) *
    Exp(-Age / 0.022);
  Result := Result * Attack;
end;

constructor TMidiAudioSourceStream.Create(Format: TAudioFormatInfo);
begin
  FFormat := Format.Copy;
  FEnvLevel := 0;
  FPhase := 0;
  FActive := False;
  FRelease := False;
  FPosition := 0;
  FNote := -1;
  FFreq := 440.0;
  FVel := 0.0;
  FNoteAge := 0.0;
  FReleaseAge := 0.0;
  FReleaseLevel := 0.0;
  FClickActive := False;
  FClickAge := 0.0;
  FClickVel := 0.0;
  System.SetLength(FEvents, 0);
  FLock := TCriticalSection.Create;
  Log.LogDebug('MidiAudioSourceStream: Created', 'MidiSynth');
end;

destructor TMidiAudioSourceStream.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TMidiAudioSourceStream.IsEOF: boolean;
begin
  Result := False;
end;

function TMidiAudioSourceStream.IsError: boolean;
begin
  Result := false;
end;

function TMidiAudioSourceStream.GetLength: real;
begin
  Result := 0; // Not implemented
end;

function TMidiAudioSourceStream.GetPosition: real;
begin
  Result := FPosition;
end;

procedure TMidiAudioSourceStream.SetPosition(Time: real);
begin
  FLock.Enter;
  try
    FPosition := Time;
    System.SetLength(FEvents, 0);
    ApplyStopAll;
  finally
    FLock.Leave;
  end;
end;

function TMidiAudioSourceStream.ReadData(Buffer: PByte; BufferSize: integer): integer;

var
  SampleRate: Integer;
  Channels: Integer;
  Frames: Integer;
  s: PSmallInt;
  i, j: Integer;
  phaseInc, sample, sampleTime, frameTime, ReleaseTime, Force: Double;
  outSample: SmallInt;
  tempSample: Int64;
begin
  SampleRate := Trunc(FFormat.SampleRate);
  Channels := Trunc(FFormat.Channels);
  Frames := BufferSize div (Channels * 2); // 2 bytes per sample
  s := PSmallInt(Buffer);
  sampleTime := 1.0 / SampleRate;

  FLock.Enter;
  try
    phaseInc := 2 * Pi * FFreq / SampleRate;
    for i := 0 to Frames - 1 do
    begin
      frameTime := FPosition + i * sampleTime;
      ProcessEvents(frameTime);
      phaseInc := 2 * Pi * FFreq / SampleRate;

      // Envelope
      if FRelease then
      begin
        FReleaseAge := FReleaseAge + sampleTime;
        ReleaseTime := OrganReleaseTime;
        if FTone = 2 then ReleaseTime := 0.070;
        FEnvLevel := FReleaseLevel * Exp(-FReleaseAge / ReleaseTime);
        if FEnvLevel <= OrganSilenceLevel then
        begin
          FEnvLevel := 0;
          FActive := False;
        end;
      end
      else if FActive then
      begin
        FNoteAge := FNoteAge + sampleTime;
        FEnvLevel := OrganEnvelope(FNoteAge);
      end;

      if FActive then
      begin
        if FTone = 2 then
        begin
          Force := HammerForce(FNoteAge, FPianoContactTime, SampleRate);
          sample := PianoFrame(FPianoModes, Force) +
            PianoFrame(FPianoBody, Force * (1 + 0.3 * ClickNoise(FNoteAge)));
        end
        else
          sample := ToneWave(FTone, FPhase, FNoteAge, FFreq, SampleRate);
        sample := sample * FVel * FEnvLevel * OrganGain;
        // FPhase handling: keep between -Pi and +Pi
        FPhase := FPhase + phaseInc;
        if FPhase > Pi then FPhase := FPhase - 2 * Pi;
      end
      else
        sample := 0;

      // Release the previous struck string briefly when the next note starts.
      if (FTone = 2) and (FPianoTailLevel > 0) then
      begin
        sample := sample + PianoFrame(FPianoTailModes, 0) *
          FPianoTailLevel * Max(0.0, 1 - FPianoTailAge / 0.080) * OrganGain;
        FPianoTailAge := FPianoTailAge + sampleTime;
        if FPianoTailAge >= 0.080 then FPianoTailLevel := 0;
      end;

      if FClickActive then
      begin
        sample := sample + SelectedClickWave(FClickSound, FClickAge) * FClickVel * ClickGain;
        FClickAge := FClickAge + sampleTime;
        if ((FClickSound = 0) and
            (Exp(-FClickAge / ClickDecayTime) <= ClickSilenceLevel)) or
           ((FClickSound <> 0) and (FClickAge >= 0.200)) then
          FClickActive := False;
      end;

      // Convert to SmallInt once per frame
      tempSample := Round(sample * High(SmallInt));
      if tempSample > High(SmallInt) then
        outSample := High(SmallInt)
      else if tempSample < Low(SmallInt) then
        outSample := Low(SmallInt)
      else
        outSample := SmallInt(tempSample);
      for j := 0 to Channels - 1 do
      begin
        s^ := outSample;
        Inc(s);
      end;
    end;

    FPosition := FPosition + Frames * sampleTime;
  finally
    FLock.Leave;
  end;

  Result := BufferSize;
end;

function TMidiAudioSourceStream.GetAudioFormatInfo: TAudioFormatInfo;
begin
  Result := FFormat;
end;

procedure TMidiAudioSourceStream.Close;
begin
  if Assigned(FFormat) then
    FreeAndNil(FFormat);
  if Assigned(FLock) then
    FreeAndNil(FLock);
end;

procedure TMidiAudioSourceStream.QueueEvent(Time: Double; Kind: TSynthEventKind; Pitch: Byte; Velocity: Byte);
var
  Index: Integer;
  Count: Integer;
begin
  if Time < 0 then
    Time := FPosition
  else if Time < FPosition then
    Time := FPosition;

  Count := System.Length(FEvents);
  System.SetLength(FEvents, Count + 1);
  Index := Count;
  while (Index > 0) and (FEvents[Index - 1].Time > Time) do
  begin
    FEvents[Index] := FEvents[Index - 1];
    Dec(Index);
  end;

  FEvents[Index].Time := Time;
  FEvents[Index].Kind := Kind;
  FEvents[Index].Pitch := Pitch;
  FEvents[Index].Velocity := Velocity;
end;

procedure TMidiAudioSourceStream.ProcessEvents(Time: Double);
var
  i: Integer;
  Event: TScheduledSynthEvent;
begin
  while (System.Length(FEvents) > 0) and (FEvents[0].Time <= Time) do
  begin
    Event := FEvents[0];
    for i := 1 to High(FEvents) do
      FEvents[i - 1] := FEvents[i];
    System.SetLength(FEvents, System.Length(FEvents) - 1);

    case Event.Kind of
      sekNoteOn:
        ApplyNoteOn(Event.Pitch, Event.Velocity);
      sekNoteOff:
        ApplyNoteOff(Event.Pitch);
      sekClick:
        ApplyClick(Event.Velocity);
      sekStopAll:
        ApplyStopAll;
    end;
  end;
end;

procedure TMidiAudioSourceStream.ApplyNoteOn(Pitch: Byte; Velocity: Byte);
begin
  if (FTone = 2) and FActive then
  begin
    FPianoTailModes := FPianoModes;
    FPianoTailLevel := FVel * FEnvLevel;
    FPianoTailAge := 0;
  end;
  FNote := Pitch;
  FFreq := 440.0 * Power(2.0, (FNote - 69) / 12.0);
  if FTone = 2 then
  begin
    StartPianoModes(FPianoModes, FFreq, FFormat.SampleRate);
    StartPianoBody(FPianoBody, FFormat.SampleRate);
    FPianoContactTime := (0.0038 - 0.002 * Velocity / 127) *
      EnsureRange(Power(440 / FFreq, 0.15), 0.65, 1.6);
  end;
  FVel := Sqr(Velocity / 127.0);
  FActive := True;
  FRelease := False;
  FEnvLevel := 0;
  FPhase := 0;
  FNoteAge := 0;
  FReleaseAge := 0;
  FReleaseLevel := 0;
end;

procedure TMidiAudioSourceStream.ApplyNoteOff(Pitch: Byte);
begin
  if (FNote = Pitch) and FActive then
  begin
    FReleaseAge := 0;
    FReleaseLevel := FEnvLevel;
    FRelease := True;
  end;
end;

procedure TMidiAudioSourceStream.ApplyClick(Velocity: Byte);
begin
  FClickActive := True;
  FClickAge := 0;
  FClickVel := Sqr(Velocity / 127.0);
end;

procedure TMidiAudioSourceStream.ApplyStopAll;
begin
  FPianoTailLevel := 0;
  FActive := False;
  FRelease := False;
  FEnvLevel := 0;
  FVel := 0;
  FNote := -1;
  FNoteAge := 0;
  FReleaseAge := 0;
  FReleaseLevel := 0;
  FClickActive := False;
  FClickAge := 0;
  FClickVel := 0;
  System.SetLength(FEvents, 0);
end;

procedure TMidiAudioSourceStream.NoteOn(Pitch: Byte; Velocity: Byte; Time: Double);
begin
  FLock.Enter;
  try
    QueueEvent(Time, sekNoteOn, Pitch, Velocity);
    ProcessEvents(FPosition);
  finally
    FLock.Leave;
  end;
end;

procedure TMidiAudioSourceStream.NoteOff(Pitch: Byte; Time: Double);
begin
  FLock.Enter;
  try
    QueueEvent(Time, sekNoteOff, Pitch, 0);
    ProcessEvents(FPosition);
  finally
    FLock.Leave;
  end;
end;

procedure TMidiAudioSourceStream.Click(Velocity: Byte; Time: Double);
begin
  FLock.Enter;
  try
    QueueEvent(Time, sekClick, 0, Velocity);
    ProcessEvents(FPosition);
  finally
    FLock.Leave;
  end;
end;

procedure TMidiAudioSourceStream.StopAll(Time: Double);
begin
  FLock.Enter;
  try
    QueueEvent(Time, sekStopAll, 0, 0);
    ProcessEvents(FPosition);
  finally
    FLock.Leave;
  end;
end;

function TMidiAudioSourceStream.GetLoop(): boolean;
begin
  Result := False;
end;

procedure TMidiAudioSourceStream.SetLoop(Enabled: boolean);
begin
  // Do nothing, MIDI synthesis doesn't loop
end;

end.
