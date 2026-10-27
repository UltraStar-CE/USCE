program audio_calibration_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses SysUtils, Math, UAudioCalibration;
const Delays: array[0..3] of integer = (25, 80, 220, 450);
var Calibration: TAudioCalibration;
    Fit: TAudioCalibrationResult;
    TimeMs, DelayMs, Tone, Trial: integer;

procedure Feed(Delay: integer; Mode: integer = 0);
var Time, EffectiveDelay, Detected: integer;
begin
  Calibration.Start(1000000);
  for Time := 0 to 399 do
  begin
    EffectiveDelay := Delay;
    if Mode = 1 then EffectiveDelay := Delay + (Time mod 3 - 1) * 10;
    Detected := AudioCalibrationNote(Time * 10000 - EffectiveDelay * 1000);
    if Mode = 2 then Detected := 0;
    if (Mode = 3) and (Time > 190) and (Time < 230) then Continue;
    if (Mode = 4) and (Detected >= 0) then Inc(Detected, 48);
    if (Mode = 5) and (Time > 250) then Break;
    Calibration.Observe(1000000 + Time * 10000, Detected, Detected >= 0);
  end;
end;

begin
  Assert(AudioCalibrationNote(-1) = -1);
  Assert(AudioCalibrationNote(AUDIO_CALIBRATION_DURATION_US) = -1);
  Calibration := TAudioCalibration.Create;
  try
    for DelayMs in Delays do
      for Trial in [0, 1, 4] do
      begin
        Feed(DelayMs, Trial);
        Fit := Calibration.Estimate(3);
        Assert(Fit.Accepted, 'Known digital delay was rejected');
        Assert(Abs(Fit.DelayMs - DelayMs) <= Fit.UncertaintyMs,
          'Known delay was outside reported uncertainty');
        Assert(Fit.UncertaintyMs < 40, 'Stable measurement became too vague');
      end;
    for Trial in [2, 3, 5] do
    begin
      Feed(80, Trial);
      Assert(not Calibration.Estimate(3).Accepted,
        'Silence, frame stalls or incomplete sequence must not set compensation');
    end;
    Feed(80);
    Assert(not Calibration.Estimate(-1).Accepted);
    Assert(not Calibration.Estimate(101).Accepted);
    Feed(0);
    Assert(not Calibration.Estimate(0).Accepted, 'Boundary fit must not be accepted');
    Feed(500);
    Assert(not Calibration.Estimate(0).Accepted, 'Search-limit fit must not be accepted');
    Calibration.Start(1000000);
    for TimeMs := 0 to 399 do
    begin
      Tone := AudioCalibrationNote(TimeMs * 10000 - 80000);
      Calibration.Observe(1000000 + TimeMs * 10000, Tone, false);
    end;
    Assert(not Calibration.Estimate(3).Accepted, 'Unvoiced data must not calibrate');
    Calibration.Start(High(int64));
    Assert(not Calibration.Estimate(0).Accepted);
    WriteLn('Digital calibration: known delays/jitter/octaves accepted; ambiguous, stalled, incomplete and unvoiced data rejected');
  finally
    Calibration.Free;
  end;
end.
