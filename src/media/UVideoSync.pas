{ Clock policy for a video decoder that runs on its own clock (libmpv).
  The game's audio clock owns the timeline; between calls the decoder plays
  on its own timer. TExternalVideoSync.Update takes the time the game
  requests, the position the decoder last reported (used only when
  HavePlayback is set), the monotonic time of the call, the duration (0 when
  unknown) and the loop, pause and end-of-file states. It returns the
  position to show (wrapped when looping, otherwise clamped to the duration),
  the playback speed (1, or 0.95 to 1.05 to absorb small drift), whether the
  decoder should be paused and whether it should seek to that position.
  The decisions are made here; UVideo_MPV only sends the resulting pause,
  speed and seek commands to libmpv and reads their acknowledgements. }
unit UVideoSync;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

type
  TVideoSyncDecision = record
    Position: double;
    Speed: double;
    Paused: boolean;
    Seek: boolean;
  end;

  { The game's audio clock owns the timeline. The decoder's clock only runs
    between samples; small differences are corrected without repeated seeks.
    Reset starts a new timeline (open, seek, loop change); Resume continues
    the current one after a pause. }
  TExternalVideoSync = class
    private
      fHaveRequest: boolean;
      fResumed: boolean;
      fLastRequest: double;
      fLastSampleTime: double;
      fLastMovementTime: double;
      fLastCorrectionTime: double;
      fLastSeekTime: double;
      fLargeDriftSince: double;
      fSpeed: double;
    public
      constructor Create;
      procedure Reset;
      procedure Resume;
      function Update(RequestedTime, PlaybackTime, ClockTime, Duration: double;
        HavePlayback, Loop, Paused, EndReached: boolean): TVideoSyncDecision;
  end;

function VideoLoopPosition(Time, Duration: double; Loop: boolean): double;

implementation

uses
  Math;

function VideoLoopPosition(Time, Duration: double; Loop: boolean): double;
begin
  { Max() with an integer literal would round to single precision. }
  if Time > 0 then
    Result := Time
  else
    Result := 0;
  if Loop and (Duration > 0) then
    Result := Result - Floor(Result / Duration) * Duration
  else if Duration > 0 then
    Result := Min(Result, Duration);
end;

constructor TExternalVideoSync.Create;
begin
  inherited Create;
  Reset;
end;

procedure TExternalVideoSync.Reset;
begin
  fHaveRequest := false;
  fResumed := false;
  fLastRequest := 0;
  fLastSampleTime := 0;
  fLastMovementTime := -1;
  fLastCorrectionTime := -1;
  fLastSeekTime := -1;
  fLargeDriftSince := -1;
  fSpeed := 1;
end;

{ The clock continues where a pause began. See the resume case in Update. }
procedure TExternalVideoSync.Resume;
begin
  Reset;
  fResumed := true;
end;

function TExternalVideoSync.Update(RequestedTime, PlaybackTime, ClockTime,
  Duration: double; HavePlayback, Loop, Paused, EndReached: boolean): TVideoSyncDecision;
var
  elapsed, delta, drift: double;
  discontinuity, firstRequest, atEnd, resumed: boolean;
begin
  Result.Position := VideoLoopPosition(RequestedTime, Duration, Loop);
  Result.Seek := false;
  { The player reports its own end: the video track may be shorter than the
    file's duration, and the duration may be unknown. }
  atEnd := not Loop and
    (EndReached or ((Duration > 0) and (RequestedTime >= Duration)));
  firstRequest := not fHaveRequest;
  discontinuity := false;
  if fHaveRequest then
  begin
    elapsed := Max(0, ClockTime - fLastSampleTime);
    delta := RequestedTime - fLastRequest;
    discontinuity := (delta < -0.050) or (delta > elapsed + 0.500);
    if delta > 0.0001 then
      fLastMovementTime := ClockTime;
  end;

  { Wait for the audio clock to move before starting. Identical timestamps
    also occur briefly because the audio clock has a coarser resolution. }
  Result.Paused := Paused or (RequestedTime <= 0) or atEnd or
    (fLastMovementTime < 0) or (ClockTime - fLastMovementTime >= 0.100);

  if HavePlayback then
  begin
    resumed := fResumed;
    fResumed := false;
    drift := Result.Position - PlaybackTime;
    { Compare the nearest positions around the loop boundary. }
    if Loop and (Duration > 0) then
    begin
      if drift > Duration / 2 then
        drift := drift - Duration
      else if drift < -Duration / 2 then
        drift := drift + Duration;
    end;

    { Positions arrive once per decoded frame, so a low frame rate shows a
      brief sawtooth. Only lag that persists is corrected with a seek. }
    if drift > 0.750 then
    begin
      if fLargeDriftSince < 0 then
        fLargeDriftSince := ClockTime;
    end
    else
      fLargeDriftSince := -1;

    { Explicit jumps seek unless the player already shows that position.
      A video running ahead of the clock waits for it, as the FFmpeg backend
      does, instead of seeking backwards; the sing screen relies on this while
      it requests the bare video gap before its transition finishes. Once the
      clock reaches EOF, hold the final frame rather than repeatedly
      correcting that expected difference.
      A resume is the exception: the clock did not move during the pause,
      so a decoder found ahead kept playing unobserved (a hidden menu
      background pumps no events, and its pause can sit behind an
      unacknowledged unpause). It is brought back instead of freezing
      the picture until the clock catches up. }
    if ((discontinuity or firstRequest) and (drift > 0.100)) or
      (discontinuity and (drift < -0.100)) or
      (resumed and (drift < -0.250)) or
      (not atEnd and (drift > 0.750) and
       (ClockTime - fLargeDriftSince >= 0.500) and
       (ClockTime - fLastSeekTime >= 1)) then
    begin
      Result.Seek := true;
      fLastSeekTime := ClockTime;
      fLastCorrectionTime := ClockTime;
      fLargeDriftSince := -1;
      fSpeed := 1;
    end
    else if drift < -0.250 then
      Result.Paused := true
    else if not Result.Paused and
      (ClockTime - fLastCorrectionTime >= 0.250) then
    begin
      fLastCorrectionTime := ClockTime;
      if Abs(drift) <= 0.040 then
        fSpeed := 1
      else
        fSpeed := EnsureRange(1 + drift * 0.2, 0.95, 1.05);
    end;
  end;

  if Result.Paused then
    fSpeed := 1;
  Result.Speed := fSpeed;
  fHaveRequest := true;
  fLastRequest := RequestedTime;
  fLastSampleTime := ClockTime;
end;

end.
