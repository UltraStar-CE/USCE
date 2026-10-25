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
    between samples; small differences are corrected without repeated seeks. }
  TExternalVideoSync = class
    private
      fHaveRequest: boolean;
      fLastRequest: double;
      fLastSampleTime: double;
      fLastMovementTime: double;
      fLastCorrectionTime: double;
      fLastSeekTime: double;
      fSpeed: double;
    public
      constructor Create;
      procedure Reset;
      function Update(RequestedTime, PlaybackTime, ClockTime, Duration: double;
        HavePlayback, Loop, Paused: boolean): TVideoSyncDecision;
  end;

function VideoLoopPosition(Time, Duration: double; Loop: boolean): double;

implementation

uses
  Math;

function VideoLoopPosition(Time, Duration: double; Loop: boolean): double;
begin
  Result := Max(0, Time);
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
  fLastRequest := 0;
  fLastSampleTime := 0;
  fLastMovementTime := -1;
  fLastCorrectionTime := -1;
  fLastSeekTime := -1;
  fSpeed := 1;
end;

function TExternalVideoSync.Update(RequestedTime, PlaybackTime, ClockTime,
  Duration: double; HavePlayback, Loop, Paused: boolean): TVideoSyncDecision;
var
  elapsed, delta, drift: double;
  discontinuity, firstRequest: boolean;
begin
  Result.Position := VideoLoopPosition(RequestedTime, Duration, Loop);
  Result.Seek := false;
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
  Result.Paused := Paused or (RequestedTime <= 0) or
    (not Loop and (Duration > 0) and (RequestedTime >= Duration)) or
    (fLastMovementTime < 0) or (ClockTime - fLastMovementTime >= 0.100);
  if Result.Paused then
    fSpeed := 1;

  if HavePlayback then
  begin
    drift := Result.Position - PlaybackTime;
    { Compare the nearest positions around the loop boundary. }
    if Loop and (Duration > 0) then
    begin
      if drift > Duration / 2 then
        drift := drift - Duration
      else if drift < -Duration / 2 then
        drift := drift + Duration;
    end;

    if discontinuity or (firstRequest and (Abs(drift) > 0.100)) or
      ((Abs(drift) > 0.750) and (ClockTime - fLastSeekTime >= 1)) then
    begin
      Result.Seek := true;
      fLastSeekTime := ClockTime;
      fLastCorrectionTime := ClockTime;
      fSpeed := 1;
    end
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

  Result.Speed := fSpeed;
  fHaveRequest := true;
  fLastRequest := RequestedTime;
  fLastSampleTime := ClockTime;
end;

end.
