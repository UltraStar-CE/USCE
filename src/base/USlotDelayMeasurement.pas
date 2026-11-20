unit USlotDelayMeasurement;
{$mode Delphi}{$H+}

interface

uses UAudioCalibration, UIni, MidiOut;

type
  TSlotDelayMeasurement = class
  private
    FOutput: TMidiOutput;
    FSlots: cardinal;
    FStartUs, FNextObservationUs: int64;
    FFits: array[0..IMaxPlayerCount-1] of TAudioCalibration;
    FOwners: array[0..IMaxPlayerCount-1] of UTF8String;
    FResults: array[0..IMaxPlayerCount-1] of TAudioCalibrationResult;
    function SameInput(Slot: integer): boolean;
    function IsMeasuring: boolean;
  public
    destructor Destroy; override;
    function Start(Slots: cardinal): boolean;
    procedure Update;
    function ResultFor(Slot: integer): TAudioCalibrationResult;
    function HasResult: boolean;
    procedure Apply(CurrentSlots: cardinal);
    property Slots: cardinal read FSlots;
    property Measuring: boolean read IsMeasuring;
  end;

implementation

uses SysUtils, URecord, URemoteInput, UPhoneAudio, UTime;

destructor TSlotDelayMeasurement.Destroy;
var Slot: integer;
begin
  FOutput.Free;
  for Slot := 0 to High(FFits) do FFits[Slot].Free;
  inherited;
end;

function TSlotDelayMeasurement.Start(Slots: cardinal): boolean;
const LeadInUs = 250000;
var Slot, Step, Pitch: integer;
    Time: double;
begin
  Result := false;
  if (Slots = 0) or (FSlots <> 0) then Exit;
  FOutput := TMidiOutput.Create(nil);
  if not FOutput.Open then
  begin
    FreeAndNil(FOutput);
    Exit;
  end;
  FSlots := Slots;
  FOutput.SetVolume(Ini.SfxVolume / 100);
  for Step := 0 to AUDIO_CALIBRATION_NOTES - 1 do
  begin
    Time := (LeadInUs + Step * AUDIO_CALIBRATION_STEP_US) / 1000000;
    Pitch := 60 + AudioCalibrationNote(Step * AUDIO_CALIBRATION_STEP_US);
    FOutput.QueueNoteOn(Pitch, 100, Time);
    FOutput.QueueNoteOff(Pitch, Time + AUDIO_CALIBRATION_STEP_US / 1000000);
  end;
  FStartUs := MonotonicMicroseconds + LeadInUs;
  FNextObservationUs := FStartUs + AUDIO_CALIBRATION_MAX_DELAY_MS * 1000;
  for Slot := 0 to High(FFits) do
    if (Slots and (cardinal(1) shl Slot)) <> 0 then
    begin
      FOwners[Slot] := RemoteInputProcessor.AssignedPlayerId(Slot);
      FFits[Slot] := TAudioCalibration.Create;
      FFits[Slot].Start(FStartUs);
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
    NowUs: int64;
    Capture: TCaptureBuffer;
begin
  if not Assigned(FOutput) then Exit;
  NowUs := MonotonicMicroseconds;
  if NowUs < FNextObservationUs then Exit;
  if NowUs >= FStartUs + AUDIO_CALIBRATION_DURATION_US then
  begin
    FreeAndNil(FOutput);
    for Slot := 0 to High(FFits) do
      if Assigned(FFits[Slot]) and SameInput(Slot) then
        FResults[Slot] := FFits[Slot].Estimate(0);
    Exit;
  end;
  FNextObservationUs := NowUs + 10000;
  for Slot := 0 to High(FFits) do
    if Assigned(FFits[Slot]) then
    begin
      if not SameInput(Slot) then
      begin
        FreeAndNil(FFits[Slot]);
        Continue;
      end;
      Capture := AudioInputProcessor.Sound[Slot];
      Capture.AnalyzeBuffer;
      FFits[Slot].Observe(NowUs, Capture.ToneAbs,
        Capture.ToneValid and (Capture.LastInputTicks > 0) and
        (GetTickCount64 - Capture.LastInputTicks <= 100));
    end;
end;

function TSlotDelayMeasurement.ResultFor(Slot: integer): TAudioCalibrationResult;
begin
  Result := FResults[Slot];
  Result.Accepted := Result.Accepted and SameInput(Slot);
end;

function TSlotDelayMeasurement.HasResult: boolean;
var Slot: integer;
begin
  Result := true;
  for Slot := 0 to High(FResults) do
    if ResultFor(Slot).Accepted then Exit;
  Result := false;
end;

procedure TSlotDelayMeasurement.Apply(CurrentSlots: cardinal);
var Slot, Baseline: integer;
    ChangedSlots: cardinal;
    Measurement: TAudioCalibrationResult;
begin
  ChangedSlots := 0;
  for Slot := 0 to High(FResults) do
  begin
    Measurement := ResultFor(Slot);
    if not Measurement.Accepted or ((CurrentSlots and (cardinal(1) shl Slot)) = 0) then Continue;
    Baseline := Ini.MicDelay;
    if (FOwners[Slot] <> '') and PhoneAudio.Enabled then
      Inc(Baseline, PhoneAudio.Calibration.EffectivePlayerDelay(Slot, Ini.MicDelay, 0));
    Ini.SlotDelay[Slot] := Measurement.DelayMs - Baseline;
    ChangedSlots := ChangedSlots or (cardinal(1) shl Slot);
  end;
  if ChangedSlots <> 0 then Ini.SaveDelays(ChangedSlots);
end;

end.
