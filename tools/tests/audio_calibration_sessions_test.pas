program audio_calibration_sessions_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses SysUtils, fpjson, jsonparser, UAudioCalibration, UAudioCalibrationSessions;
var Sessions: TAudioCalibrationSessions;
    Message: UTF8String; Data: TJSONObject;
    I, Lane, Tone, Fitted, Effective: integer;
    StartUs, NowUs: int64;
begin
  Sessions := TAudioCalibrationSessions.Create;
  try
    Assert(not Sessions.Queue(-1, 'p', 'id', 0, 1000000));
    Assert(not Sessions.Queue(12, 'p', 'id', 0, 1000000));
    Assert(not Sessions.Queue(0, '', 'id', 0, 1000000));
    Assert(not Sessions.Queue(0, 'p', '', 0, 1000000));
    Assert(not Sessions.Queue(0, 'p', 'id', 101, 1000000));
    // Every lane runs independently and replies only to its requesting player.
    for Lane := 0 to 11 do
    begin
      Assert(Sessions.Queue(Lane, 'p'+IntToStr(Lane), 'trial'+IntToStr(Lane), 3, 1000000));
      Assert(not Sessions.Queue(Lane, 'other', 'overwrite', 0, 1000001));
      Assert(not Sessions.Tick(Lane, 'p'+IntToStr(Lane), true, true, 1001000, Message));
      Data := TJSONObject(GetJSON(string(Message)));
      try
        Assert(Data.Get('type', '') = 'audio.calibration.started');
        Assert(Data.Get('playerId', '') = 'p'+IntToStr(Lane));
        Assert(Data.Get('requestId', '') = 'trial'+IntToStr(Lane));
        Assert(Data.Arrays['notes'].Count = 16);
        StartUs := Data.Get('startHostUs', int64(0));
      finally Data.Free; end;
      for I := 0 to 399 do
      begin
        NowUs := StartUs + I * 10000;
        Tone := AudioCalibrationNote(I * 10000 - 80000);
        Assert(Sessions.Tick(Lane, 'p'+IntToStr(Lane), true, true, NowUs, Message));
        Assert(Message = '');
        Sessions.Observe(Lane, NowUs, Tone, Tone >= 0);
      end;
      Assert(not Sessions.Tick(Lane, 'p'+IntToStr(Lane), true, true,
        StartUs + AUDIO_CALIBRATION_DURATION_US, Message));
      Data := TJSONObject(GetJSON(string(Message)));
      try
        Assert(Data.Get('accepted', false));
        Assert(Data.Get('requestId', '') = 'trial'+IntToStr(Lane));
        Fitted := Data.Get('delayMs', -1);
        Assert(Abs(Fitted - 80) < 15);
      finally Data.Free; end;
      Effective := Sessions.EffectivePlayerDelay(Lane, 140, 20);
      Assert(140 + Effective = Fitted + 20, 'Global delay must not be applied twice');
      Assert(Sessions.EffectivePlayerDelay(Lane, 0, 20) = Fitted + 20);
      Sessions.Tick(Lane, 'replacement', true, true, StartUs + 5000000, Message);
      Assert(Sessions.EffectivePlayerDelay(Lane, 140, 20) = 20,
        'Replacement singer must not inherit another device calibration');
    end;
    Assert(Sessions.Queue(0, 'replacement', 'interrupted', 0, 20000000));
    Sessions.Tick(0, 'replacement', true, true, 20000001, Message);
    Sessions.Tick(0, 'replacement', false, true, 21000000, Message);
    Data := TJSONObject(GetJSON(string(Message)));
    try
      Assert(not Data.Get('accepted', true));
      Assert(Data.Get('reason', '') = 'interrupted');
    finally Data.Free; end;
    Assert(Sessions.EffectivePlayerDelay(0, 140, -20) = -20);
    WriteLn('Calibration sessions: twelve lanes, ownership, cancellation and compensation without double global delay passed');
  finally Sessions.Free; end;
end.
