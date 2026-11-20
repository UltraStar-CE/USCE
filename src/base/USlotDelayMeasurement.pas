unit USlotDelayMeasurement;
{$mode Delphi}{$H+}

interface

uses UAudioCalibration, UIni, MidiOut, UTime;

type
  TSlotDelayMeasurement = class
  private
    FOutput: TMidiOutput;
    FSlots: cardinal;
    FAttempt: integer;
    FStartUs, FNextObservationUs, FReadbackUs, FPlaybackOriginUs: int64;
    FPlaybackPhase: TPlaybackPhase;
    FLiveFits, FCaptureFits: array[0..IMaxPlayerCount-1] of TAudioCalibration;
    FOwners: array[0..IMaxPlayerCount-1] of UTF8String;
    FLiveResults, FCaptureResults: array[0..IMaxPlayerCount-1] of TAudioCalibrationResult;
    function StartAttempt: boolean;
    function SameInput(Slot: integer): boolean;
    function IsMeasuring: boolean;
    function CaptureResultFor(Slot: integer): TAudioCalibrationResult;
  public
    destructor Destroy; override;
    function Start(Slots: cardinal): boolean;
    procedure Update;
    function ResultFor(Slot: integer): TAudioCalibrationResult;
    function HasResult: boolean;
    procedure Apply(CurrentSlots: cardinal);
    property Attempt: integer read FAttempt;
    property Slots: cardinal read FSlots;
    property Measuring: boolean read IsMeasuring;
  end;

implementation

uses SysUtils, URecord, URemoteInput, UPhoneAudio;

const
  LeadInUs = 250000;
  MaxAttempts = 5;
  CaptureReadbackUs = AUDIO_CALIBRATION_MAX_DELAY_MS * 1000;

procedure KeepBestFit(var Best: TAudioCalibrationResult; const Candidate: TAudioCalibrationResult);
begin
  if Candidate.HasEstimate and (not Best.HasEstimate or Candidate.Accepted or
    (not Best.Accepted and
      ((Candidate.Matches * Best.Observations > Best.Matches * Candidate.Observations) or
       ((Candidate.Matches * Best.Observations = Best.Matches * Candidate.Observations) and
        (Candidate.UncertaintyMs < Best.UncertaintyMs))))) then
    Best := Candidate;
end;

destructor TSlotDelayMeasurement.Destroy;
var Slot: integer;
begin
  FOutput.Free;
  for Slot := 0 to High(FLiveFits) do
  begin
    FLiveFits[Slot].Free;
    FCaptureFits[Slot].Free;
  end;
  inherited;
end;

function TSlotDelayMeasurement.Start(Slots: cardinal): boolean;
var Slot: integer;
begin
  Result := false;
  if (Slots = 0) or (FSlots <> 0) then Exit;
  FSlots := Slots;
  for Slot := 0 to High(FLiveFits) do
    if (Slots and (cardinal(1) shl Slot)) <> 0 then
    begin
      FOwners[Slot] := RemoteInputProcessor.AssignedPlayerId(Slot);
      FLiveFits[Slot] := TAudioCalibration.Create;
      if (FOwners[Slot] <> '') and PhoneAudio.SupportsCaptureTimestamps then
      begin
        FCaptureFits[Slot] := TAudioCalibration.Create;
        FReadbackUs := CaptureReadbackUs;
      end;
    end;
  Result := StartAttempt;
end;

function TSlotDelayMeasurement.StartAttempt: boolean;
var Slot, Step, Pitch: integer;
    ToneTime: double;
begin
  Result := false;
  FOutput := TMidiOutput.Create(nil);
  if not FOutput.Open then
  begin
    FreeAndNil(FOutput);
    Exit;
  end;
  Inc(FAttempt);
  FPlaybackPhase := Default(TPlaybackPhase);
  FPlaybackOriginUs := 0;
  FOutput.SetVolume(Ini.SfxVolume / 100);
  for Step := 0 to AUDIO_CALIBRATION_NOTES - 1 do
  begin
    ToneTime := (LeadInUs + Step * AUDIO_CALIBRATION_STEP_US) / 1000000;
    Pitch := 60 + AudioCalibrationNote(Step * AUDIO_CALIBRATION_STEP_US);
    FOutput.QueueNoteOn(Pitch, 100, ToneTime);
    FOutput.QueueNoteOff(Pitch, ToneTime + AUDIO_CALIBRATION_STEP_US / 1000000);
  end;
  FStartUs := MonotonicMicroseconds + LeadInUs;
  FNextObservationUs := FStartUs + AUDIO_CALIBRATION_MAX_DELAY_MS * 1000;
  for Slot := 0 to High(FLiveFits) do
  begin
    if Assigned(FLiveFits[Slot]) then FLiveFits[Slot].Start(FStartUs);
    if Assigned(FCaptureFits[Slot]) then FCaptureFits[Slot].Start(FStartUs);
  end;
  FOutput.Play;
  Result := true;
end;

function TSlotDelayMeasurement.IsMeasuring: boolean;
begin
  Result := Assigned(FOutput);
end;

function TSlotDelayMeasurement.SameInput(Slot: integer): boolean;
begin
  Result := FOwners[Slot] = RemoteInputProcessor.AssignedPlayerId(Slot);
end;

procedure TSlotDelayMeasurement.Update;
var Slot: integer;
    NowUs, EndUs, ClockUs, CaptureUs, ObservationUs, WindowCenterUs, PlaybackOriginUs: int64;
    PlaybackPosition: double;
    Capture: TCaptureBuffer;
    CaptureFit: TAudioCalibrationResult;
    Retry: boolean;
begin
  if not Assigned(FOutput) then Exit;
  NowUs := MonotonicMicroseconds;
  if NowUs < FNextObservationUs then Exit;
  EndUs := FStartUs + AUDIO_CALIBRATION_DURATION_US;
  if NowUs >= EndUs + FReadbackUs + 300000 then
  begin
    FreeAndNil(FOutput);
    Retry := false;
    for Slot := 0 to High(FLiveFits) do
      if Assigned(FLiveFits[Slot]) and SameInput(Slot) then
      begin
        KeepBestFit(FLiveResults[Slot], FLiveFits[Slot].Estimate(0));
        CaptureFit := Default(TAudioCalibrationResult);
        if Assigned(FCaptureFits[Slot]) then
        begin
          CaptureFit := FCaptureFits[Slot].Estimate(0);
          KeepBestFit(FCaptureResults[Slot], CaptureFit);
        end;
        if FCaptureResults[Slot].Accepted or
           (FLiveResults[Slot].Accepted and (CaptureFit.Observations = 0)) then
        begin
          FreeAndNil(FLiveFits[Slot]);
          FreeAndNil(FCaptureFits[Slot]);
        end
        else Retry := true;
      end;
    if Retry and (FAttempt < MaxAttempts) then StartAttempt;
    Exit;
  end;
  FNextObservationUs := NowUs + 10000;
  PlaybackPosition := FOutput.PlaybackPosition;
  ClockUs := MonotonicMicroseconds;
  if (PlaybackPosition >= 0.35) and (PlaybackPosition <= 3.85) then
    FPlaybackOriginUs := FPlaybackPhase.Observe(ClockUs, PlaybackPosition);
  PlaybackOriginUs := FPlaybackOriginUs;
  CaptureUs := int64(GetTickCount64) * 1000 - CaptureReadbackUs;
  for Slot := 0 to High(FLiveFits) do
    if Assigned(FLiveFits[Slot]) then
    begin
      if not SameInput(Slot) then
      begin
        FreeAndNil(FLiveFits[Slot]);
        FreeAndNil(FCaptureFits[Slot]);
        Continue;
      end;
      Capture := AudioInputProcessor.Sound[Slot];
      if NowUs < EndUs + 300000 then
      begin
        Capture.AnalyzeBuffer(WindowCenterUs);
        ObservationUs := NowUs;
        if WindowCenterUs <> 0 then
          ObservationUs := FStartUs + WindowCenterUs - PlaybackOriginUs - LeadInUs;
        if (WindowCenterUs = 0) or (PlaybackOriginUs <> 0) then
          FLiveFits[Slot].Observe(ObservationUs, Capture.ToneAbs,
          Capture.ToneValid and (Capture.LastInputTicks > 0) and
          (GetTickCount64 - Capture.LastInputTicks <= 100));
      end;
      if Assigned(FCaptureFits[Slot]) and (PlaybackOriginUs <> 0) then
      begin
        // Compare the retained sample's capture time to the measured playback clock.
        ObservationUs := FStartUs + ClockUs - CaptureReadbackUs - PlaybackOriginUs - LeadInUs;
        if Capture.AnalyzePhoneWindow(Slot, CaptureUs) then
          FCaptureFits[Slot].Observe(ObservationUs, Capture.ToneAbs, Capture.ToneValid);
      end;
    end;
end;

function TSlotDelayMeasurement.CaptureResultFor(Slot: integer): TAudioCalibrationResult;
begin
  Result := FCaptureResults[Slot];
  Result.HasEstimate := Result.HasEstimate and SameInput(Slot);
  Result.Accepted := Result.Accepted and SameInput(Slot);
end;

function TSlotDelayMeasurement.ResultFor(Slot: integer): TAudioCalibrationResult;
begin
  Result := CaptureResultFor(Slot);
  if Result.HasEstimate then Exit;
  Result := FLiveResults[Slot];
  Result.HasEstimate := Result.HasEstimate and SameInput(Slot);
  Result.Accepted := Result.Accepted and SameInput(Slot);
end;

function TSlotDelayMeasurement.HasResult: boolean;
var Slot: integer;
begin
  Result := true;
  for Slot := 0 to High(FLiveResults) do
    if ResultFor(Slot).HasEstimate then Exit;
  Result := false;
end;

procedure TSlotDelayMeasurement.Apply(CurrentSlots: cardinal);
var Slot, Baseline: integer;
    ChangedSlots: cardinal;
    PlayerId, CalibrationId: UTF8String;
    Measurement: TAudioCalibrationResult;
begin
  ChangedSlots := 0;
  for Slot := 0 to High(FLiveResults) do
  begin
    if (CurrentSlots and (cardinal(1) shl Slot)) = 0 then Continue;
    Measurement := ResultFor(Slot);
    if not Measurement.HasEstimate then Continue;
    if CaptureResultFor(Slot).HasEstimate then
    begin
      RemoteInputProcessor.GetAssignedPlayerIds(Slot, PlayerId, CalibrationId);
      if PlayerId = FOwners[Slot] then
        PhoneAudio.Calibration.SetCaptureOffset(CalibrationId, Measurement.DelayMs);
      Continue;
    end;
    Baseline := Ini.MicDelay;
    if (FOwners[Slot] <> '') and PhoneAudio.Enabled then
      Baseline := Ini.MicDelay + PhoneAudio.Calibration.EffectivePlayerDelay(Slot, Ini.MicDelay, 0) +
        RemoteInputProcessor.AssignedMicDelayMs(Slot);
    Ini.SlotDelay[Slot] := Measurement.DelayMs - Baseline;
    ChangedSlots := ChangedSlots or (cardinal(1) shl Slot);
  end;
  if ChangedSlots <> 0 then Ini.SaveDelays(ChangedSlots);
end;

end.
