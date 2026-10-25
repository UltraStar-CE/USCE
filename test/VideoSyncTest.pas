program VideoSyncTest;

{$MODE Delphi}

uses
  SysUtils,
  Math,
  UVideoSync;

var
  sync: TExternalVideoSync;
  decision: TVideoSyncDecision;
  t: double;

procedure Check(Value: boolean; const Message: string);
begin
  if not Value then
    raise Exception.Create(Message);
end;

begin
  sync := TExternalVideoSync.Create;
  try
    decision := sync.Update(-2, 0, 0, 10, true, false, false, false);
    Check(decision.Paused and not decision.Seek and (decision.Position = 0),
      'Negative video gap must hold the first frame');
    decision := sync.Update(-1, 0, 1, 10, true, false, false, false);
    Check(decision.Paused, 'A moving negative clock must stay paused');
    decision := sync.Update(0.02, 0, 2.02, 10, true, false, false, false);
    Check(not decision.Paused and not decision.Seek, 'Playback should begin at video time zero');

    sync.Reset;
    decision := sync.Update(5, 5, 0, 10, true, false, false, false);
    Check(decision.Paused, 'Do not run ahead of a stationary startup clock');
    decision := sync.Update(5, 5, 1, 10, true, false, false, false);
    Check(decision.Paused, 'The startup clock can stay stationary indefinitely');
    decision := sync.Update(5.02, 5, 1.02, 10, true, false, false, false);
    Check(not decision.Paused, 'Resume when the external clock starts');
    decision := sync.Update(5.02, 5.02, 1.03, 10, true, false, false, false);
    Check(not decision.Paused, 'Tolerate audio-clock timestamp granularity');
    decision := sync.Update(5.02, 5.12, 1.20, 10, true, false, false, false);
    Check(decision.Paused, 'Pause if the external clock stops');

    sync.Reset;
    decision := sync.Update(0, 0, 0, 10, true, false, false, false);
    decision := sync.Update(0.5, 0.3, 0.5, 10, true, false, false, false);
    Check(not decision.Seek and (decision.Speed > 1) and (decision.Speed <= 1.05),
      'Small positive drift should speed up without seeking');
    decision := sync.Update(1, 1.2, 1, 10, true, false, false, false);
    Check(not decision.Seek and (decision.Speed < 1) and (decision.Speed >= 0.95),
      'Small negative drift should slow down without seeking');
    decision := sync.Update(1.5, 1.5, 1.5, 10, true, false, false, false);
    Check(decision.Speed = 1, 'Return to normal speed inside the deadband');
    decision := sync.Update(7, 1.52, 1.52, 10, true, false, false, false);
    Check(decision.Seek and (decision.Position = 7), 'Seek on a forward discontinuity');
    decision := sync.Update(2, 7, 1.54, 10, true, false, true, false);
    Check(decision.Seek and decision.Paused and (decision.Position = 2),
      'A backward seek must also work while paused');

    sync.Reset;
    decision := sync.Update(9.9, 9.9, 0, 10, true, true, false, false);
    decision := sync.Update(10.02, 9.98, 0.12, 10, true, true, false, false);
    Check(not decision.Seek and (Abs(decision.Position - 0.02) < 0.000001),
      'A loop boundary must not trigger a discontinuity seek');
    decision := sync.Update(20.1, 0.1, 10.2, 10, true, true, false, false);
    Check(not decision.Seek and (Abs(decision.Position - 0.1) < 0.000001),
      'Multiple loops must map the external clock into the video');

    sync.Reset;
    decision := sync.Update(4, 0, 0, 10, true, false, false, false);
    Check(decision.Seek and decision.Paused, 'Initial nonzero position needs a seek before playing');
    decision := sync.Update(4.01, 0, 0.01, 10, false, false, false, false);
    Check(not decision.Seek, 'Do not issue corrections while a seek is outstanding');

    { The sing screen positions the video at the song start, then requests the
      bare video gap until its transition finishes. Hold the positioned frame
      instead of seeking back, and do not seek again when the clock arrives. }
    sync.Reset;
    decision := sync.Update(0, 4, 0, 10, true, false, false, false);
    Check(decision.Paused and not decision.Seek,
      'Hold a video positioned ahead of a provisional request');
    decision := sync.Update(0, 4, 0.5, 10, true, false, false, false);
    Check(decision.Paused and not decision.Seek, 'Keep holding while the request stays behind');
    decision := sync.Update(4, 4, 0.52, 10, true, false, false, false);
    Check(not decision.Seek, 'A jump onto the current playback position needs no seek');
    decision := sync.Update(4.02, 4, 0.54, 10, true, false, false, false);
    Check(not decision.Seek and not decision.Paused,
      'Resume once the clock moves past the held position');
    decision := sync.Update(4.5, 4.8, 1.02, 10, true, false, false, false);
    Check(decision.Paused and not decision.Seek,
      'A video that runs ahead waits for the clock instead of seeking back');
    decision := sync.Update(4.82, 4.8, 1.34, 10, true, false, false, false);
    Check(not decision.Paused and not decision.Seek, 'Continue once the clock has caught up');

    { Playback positions arrive once per decoded frame. A low frame rate
      produces brief sawtooth drift that must not cause corrective seeks. }
    sync.Reset;
    decision := sync.Update(0, 0, 0, 10, true, false, false, false);
    t := 0;
    while t < 4.95 do
    begin
      t := t + 0.1;
      decision := sync.Update(t, Floor(t + 0.000001), t, 10, true, false, false, false);
      Check(not decision.Seek, 'A one-frame-per-second video must not seek');
    end;

    sync.Reset;
    decision := sync.Update(0, 0, 0, 10, true, false, false, false);
    decision := sync.Update(1.0, 0.1, 1.0, 10, true, false, false, false);
    Check(not decision.Seek and (decision.Speed > 1), 'Large drift speeds up before seeking');
    decision := sync.Update(1.3, 0.1, 1.3, 10, true, false, false, false);
    Check(not decision.Seek, 'Large drift must persist before a corrective seek');
    decision := sync.Update(1.6, 0.1, 1.6, 10, true, false, false, false);
    Check(decision.Seek and (Abs(decision.Position - 1.6) < 0.000001), 'Persistent large drift seeks');

    sync.Reset;
    decision := sync.Update(9.9, 9.9, 0, 10, true, false, false, false);
    decision := sync.Update(10.8, 9.96, 0.9, 10, true, false, false, false);
    Check(not decision.Seek and decision.Paused and (decision.Position = 10),
      'Hold the last video frame when the audio continues beyond video EOF');
    decision := sync.Update(12, 9.96, 2.1, 10, true, false, false, false);
    Check(not decision.Seek and decision.Paused, 'Do not repeatedly seek past EOF');
    decision := sync.Update(3, 9.96, 2.12, 10, true, false, false, false);
    Check(decision.Seek and (decision.Position = 3), 'Allow seeking backwards from EOF');

    sync.Reset;
    decision := sync.Update(9, 9, 0, 10, true, false, false, false);
    decision := sync.Update(10.1, 9, 1.1, 10, true, false, false, false);
    Check(not decision.Seek and decision.Paused,
      'A long final frame must not trigger a corrective seek at EOF');
    decision := sync.Update(11.2, 9, 2.2, 10, true, false, false, false);
    Check(not decision.Seek and decision.Paused,
      'A long final frame must remain visible while the audio continues');
    decision := sync.Update(3, 9, 2.21, 10, true, false, true, false);
    Check(decision.Seek and decision.Paused and (decision.Position = 3),
      'Seek back from a long final frame even while paused');
    decision := sync.Update(3.1, 3, 2.31, 10, true, false, false, false);
    Check(not decision.Seek and not decision.Paused,
      'Resume the moving clock after seeking back from EOF');
    decision := sync.Update(20, 3.1, 2.32, 10, true, false, false, false);
    Check(decision.Seek and decision.Paused and (decision.Position = 10),
      'An explicit forward jump beyond EOF still positions the video');
    decision := sync.Update(20.02, 9, 2.34, 10, true, false, false, false);
    Check(not decision.Seek and decision.Paused,
      'Hold the final frame after a forward jump beyond EOF');

    sync.Reset;
    decision := sync.Update(20, 0, 0, 10, true, false, false, false);
    Check(decision.Seek and decision.Paused and (decision.Position = 10),
      'Initial positioning beyond EOF must still seek');
    decision := sync.Update(21.1, 9, 1.1, 10, true, false, false, false);
    Check(not decision.Seek and decision.Paused,
      'Initial positioning beyond EOF must not repeat its seek');
    // SetLoop resets the synchronizer before remapping the existing clock.
    sync.Reset;
    decision := sync.Update(21.1, 9, 1.1, 10, true, true, false, false);
    Check(decision.Seek and (Abs(decision.Position - 1.1) < 0.000001),
      'Enabling a loop after EOF must seek to the wrapped position');
    decision := sync.Update(21.2, 1.1, 1.2, 10, true, true, false, false);
    Check(not decision.Seek and not decision.Paused,
      'A loop enabled after EOF must resume with the moving clock');

    { The player reports its own end of playback. The video track may end
      before the file's duration, and the duration may be unknown. }
    sync.Reset;
    decision := sync.Update(9, 9, 0, 0, true, false, false, false);
    decision := sync.Update(10.1, 9.5, 1.1, 0, true, false, false, true);
    Check(not decision.Seek and decision.Paused,
      'Hold at the reported end of a video with unknown duration');
    decision := sync.Update(12, 9.5, 3.0, 0, true, false, false, true);
    Check(not decision.Seek and decision.Paused, 'Do not seek past the reported end');
    decision := sync.Update(3, 9.5, 3.02, 0, true, false, false, true);
    Check(decision.Seek and (decision.Position = 3), 'Jump back from the reported end');
    sync.Reset;
    decision := sync.Update(9, 9, 0, 12, true, false, false, false);
    decision := sync.Update(10.5, 9.5, 1.5, 12, true, false, false, true);
    Check(not decision.Seek and decision.Paused,
      'A video track shorter than the file duration holds its last frame');
    decision := sync.Update(11.9, 9.5, 2.9, 12, true, false, false, true);
    Check(not decision.Seek and decision.Paused,
      'Keep holding a short video track until the clock passes the file duration');
  finally
    sync.Free;
  end;
  WriteLn('VideoSyncTest: all checks passed');
end.
