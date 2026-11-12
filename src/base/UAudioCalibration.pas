{ Fit game-detected pitch observations to a bounded digital calibration ladder.
  All times use the game's monotonic clock. This does not measure microphone
  hardware/capture buffers, nor infer one-way delay from half an RTT. }
unit UAudioCalibration;
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

const
  AUDIO_CALIBRATION_STEP_US = 250000;
  AUDIO_CALIBRATION_NOTES = 16;
  AUDIO_CALIBRATION_DURATION_US = AUDIO_CALIBRATION_STEP_US * AUDIO_CALIBRATION_NOTES;
  AUDIO_CALIBRATION_MAX_DELAY_MS = 500;

type
  TAudioCalibrationResult = record
    Accepted: boolean;
    DelayMs, UncertaintyMs, Observations, Matches: integer;
  end;
  TAudioCalibration = class
  private
    FStartUs, FLastUs, FMaxGapUs: int64;
    FCount, FTransitions, FLastTone: integer;
    FTimes: array[0..511] of int64;
    FTones: array[0..511] of integer;
  public
    procedure Start(StartHostUs: int64);
    procedure Observe(HostUs: int64; Tone: integer; Valid: boolean);
    function Estimate(ClockUncertaintyMs: integer): TAudioCalibrationResult;
  end;

function AudioCalibrationNote(ElapsedUs: int64): integer;

implementation

uses Math;

function AudioCalibrationNote(ElapsedUs: int64): integer;
const Notes: array[0..AUDIO_CALIBRATION_NOTES-1] of integer =
  (0, 2, 4, 5, 7, 9, 11, 12, 11, 9, 7, 5, 4, 2, 0, 5);
begin
  Result := -1;
  if (ElapsedUs < 0) or (ElapsedUs >= AUDIO_CALIBRATION_DURATION_US) then Exit;
  Result := Notes[ElapsedUs div AUDIO_CALIBRATION_STEP_US];
end;

procedure TAudioCalibration.Start(StartHostUs: int64);
begin
  FStartUs := 0;
  if (StartHostUs > 0) and (StartHostUs < High(int64) - 10000000) then
    FStartUs := StartHostUs;
  FLastUs := 0;
  FMaxGapUs := 0;
  FCount := 0;
  FTransitions := 0;
  FLastTone := -1;
end;

procedure TAudioCalibration.Observe(HostUs: int64; Tone: integer; Valid: boolean);
var Elapsed: int64;
begin
  if (FStartUs = 0) or (HostUs < FStartUs) then Exit;
  Elapsed := HostUs - FStartUs;
  // Use the same observations for every candidate delay, avoiding an edge bias.
  if (Elapsed < AUDIO_CALIBRATION_MAX_DELAY_MS * 1000) or
    (Elapsed >= AUDIO_CALIBRATION_DURATION_US) or (FCount = Length(FTones)) then Exit;
  if (FLastUs > 0) and (HostUs - FLastUs < 10000) then Exit;
  if FLastUs > 0 then FMaxGapUs := Max(FMaxGapUs, HostUs - FLastUs);
  FLastUs := HostUs;
  if not Valid or (Tone < 0) then Tone := -1 else Tone := Tone mod 12;
  if Tone >= 0 then
  begin
    if (FLastTone >= 0) and (FLastTone <> Tone) then Inc(FTransitions);
    FLastTone := Tone;
  end;
  FTimes[FCount] := Elapsed;
  FTones[FCount] := Tone;
  Inc(FCount);
end;

function TAudioCalibration.Estimate(ClockUncertaintyMs: integer): TAudioCalibrationResult;
var Scores: array[0..AUDIO_CALIBRATION_MAX_DELAY_MS div 5] of integer;
    I, Candidate, Expected, Best, Tolerance, LowDelay, HighDelay: integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Observations := FCount;
  if (FCount < 80) or (FTransitions < 8) or (FMaxGapUs > 100000) or
    (ClockUncertaintyMs < 0) or (ClockUncertaintyMs > 100) then Exit;
  if FTimes[FCount-1] < AUDIO_CALIBRATION_DURATION_US - 100000 then Exit;
  Best := 0;
  for Candidate := Low(Scores) to High(Scores) do
  begin
    Scores[Candidate] := 0;
    for I := 0 to FCount-1 do
    begin
      Expected := AudioCalibrationNote(FTimes[I] - Candidate * 5000);
      if (Expected >= 0) and (FTones[I] = Expected mod 12) then Inc(Scores[Candidate]);
    end;
    Best := Max(Best, Scores[Candidate]);
  end;
  Result.Matches := Best;
  if Best * 100 < FCount * 80 then Exit;
  Tolerance := Max(1, FCount div 100);
  LowDelay := -1;
  HighDelay := -1;
  for Candidate := Low(Scores) to High(Scores) do
    if Scores[Candidate] >= Best - Tolerance then
    begin
      if LowDelay < 0 then LowDelay := Candidate * 5;
      HighDelay := Candidate * 5;
    end;
  // A flat/ambiguous fit or a minimum at the search boundary cannot justify
  // changing compensation. Keep the previous valid result instead.
  if (LowDelay <= 0) or (HighDelay >= AUDIO_CALIBRATION_MAX_DELAY_MS) or
    (HighDelay - LowDelay > 80) then Exit;
  Result.DelayMs := (LowDelay + HighDelay) div 2;
  // Include the observation cadence: a 40 ms game frame must not claim the
  // same temporal precision as the 10 ms synthetic unit-test observations.
  Result.UncertaintyMs := (HighDelay - LowDelay + 1) div 2 + ClockUncertaintyMs +
    (FMaxGapUs + 1999) div 2000;
  Result.Accepted := true;
end;

end.
