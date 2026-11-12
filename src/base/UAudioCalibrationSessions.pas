{ Bounded per-microphone calibration sessions. The I/O thread queues requests;
  only the game thread supplies observations from its own pitch detector. }
unit UAudioCalibrationSessions;
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface
uses SysUtils, UAudioCalibration;
type
  TAudioCalibrationSessions = class
  private
    type TLane = record
      Owner, RequestPlayer, RequestId: UTF8String;
      Pending, Active, Calibrated: boolean;
      RequestedUs, StartUs, LastRequestUs: int64;
      ClockUncertaintyMs: integer;
      Fit: TAudioCalibrationResult;
      Estimator: TAudioCalibration;
    end;
    var FLanes: array[0..11] of TLane;
        FLock: TRTLCriticalSection;
    function Reply(Index: integer; const Kind, Reason: string): UTF8String;
  public
    constructor Create;
    destructor Destroy; override;
    function Queue(Index: integer; const PlayerId, RequestId: UTF8String;
      ClockUncertaintyMs: integer; NowUs: int64): boolean;
    function Tick(Index: integer; const CurrentPlayer: UTF8String;
      Idle, StreamLive: boolean; NowUs: int64; out Message: UTF8String): boolean;
    procedure Observe(Index: integer; NowUs: int64; Tone: integer; Valid: boolean);
    procedure Cancel(Index: integer; const PlayerId, RequestId: UTF8String);
    function EffectivePlayerDelay(Index, GlobalDelayMs, ManualTrimMs: integer): integer;
  end;
implementation
uses Math, fpjson;

constructor TAudioCalibrationSessions.Create;
var I: integer;
begin
  inherited Create;
  InitCriticalSection(FLock);
  for I := Low(FLanes) to High(FLanes) do FLanes[I].Estimator := TAudioCalibration.Create;
end;

destructor TAudioCalibrationSessions.Destroy;
var I: integer;
begin
  for I := Low(FLanes) to High(FLanes) do FLanes[I].Estimator.Free;
  DoneCriticalSection(FLock);
  inherited;
end;

function TAudioCalibrationSessions.Queue(Index: integer; const PlayerId,
  RequestId: UTF8String; ClockUncertaintyMs: integer; NowUs: int64): boolean;
begin
  Result := false;
  if (Index < 0) or (Index > High(FLanes)) or (PlayerId = '') or
    (Length(PlayerId) > 128) or (RequestId = '') or (Length(RequestId) > 64) or
    (ClockUncertaintyMs < 0) or (ClockUncertaintyMs > 100) or
    (NowUs <= 0) or (NowUs > High(int64) - 10000000) then Exit;
  EnterCriticalSection(FLock);
  try
    if FLanes[Index].Pending or FLanes[Index].Active or
      ((FLanes[Index].LastRequestUs > 0) and
       (NowUs - FLanes[Index].LastRequestUs < 10000000)) then Exit;
    FLanes[Index].RequestPlayer := PlayerId;
    FLanes[Index].RequestId := RequestId;
    FLanes[Index].ClockUncertaintyMs := ClockUncertaintyMs;
    FLanes[Index].RequestedUs := NowUs;
    FLanes[Index].LastRequestUs := NowUs;
    FLanes[Index].Pending := true;
    Result := true;
  finally LeaveCriticalSection(FLock); end;
end;

function TAudioCalibrationSessions.Reply(Index: integer; const Kind, Reason: string): UTF8String;
var Obj: TJSONObject; Notes: TJSONArray; I: integer;
begin
  with FLanes[Index] do
  begin
    Obj := TJSONObject.Create(['type', Kind, 'playerId', string(RequestPlayer),
      'requestId', string(RequestId), 'slot', Index + 1, 'scope', 'digital-path']);
    try
      if Kind = 'audio.calibration.started' then
      begin
        Obj.Add('startHostUs', StartUs);
        Obj.Add('stepUs', AUDIO_CALIBRATION_STEP_US);
        Notes := TJSONArray.Create;
        for I := 0 to AUDIO_CALIBRATION_NOTES-1 do
          Notes.Add(AudioCalibrationNote(int64(I) * AUDIO_CALIBRATION_STEP_US));
        Obj.Add('notes', Notes);
      end
      else
      begin
        Obj.Add('accepted', Calibrated and (Reason = ''));
        Obj.Add('reason', Reason);
        Obj.Add('delayMs', Fit.DelayMs);
        Obj.Add('uncertaintyMs', Fit.UncertaintyMs);
        Obj.Add('observations', Fit.Observations);
        Obj.Add('matches', Fit.Matches);
      end;
      Result := UTF8String(Obj.AsJSON);
    finally Obj.Free; end;
  end;
end;

function TAudioCalibrationSessions.Tick(Index: integer; const CurrentPlayer: UTF8String;
  Idle, StreamLive: boolean; NowUs: int64; out Message: UTF8String): boolean;
begin
  Result := false;
  Message := '';
  if (Index < 0) or (Index > High(FLanes)) then Exit;
  EnterCriticalSection(FLock);
  try
    with FLanes[Index] do
    begin
      if Owner <> CurrentPlayer then
      begin
        if Active then Message := Reply(Index, 'audio.calibration.result', 'interrupted');
        Owner := CurrentPlayer;
        Active := false;
        Calibrated := false;
        if not Pending then LastRequestUs := 0;
      end;
      if Pending then
      begin
        Pending := false;
        if not Idle or not StreamLive or (CurrentPlayer <> RequestPlayer) or
          (NowUs < RequestedUs) or (NowUs - RequestedUs > 2000000) then
        begin
          Message := Reply(Index, 'audio.calibration.result', 'input_not_ready');
          Exit;
        end;
        Calibrated := false;
        FillChar(Fit, SizeOf(Fit), 0);
        StartUs := NowUs + 750000;
        Estimator.Start(StartUs);
        Active := true;
        Message := Reply(Index, 'audio.calibration.started', '');
      end;
      if not Active then Exit;
      if not Idle or not StreamLive or (CurrentPlayer <> RequestPlayer) then
      begin
        Active := false;
        Message := Reply(Index, 'audio.calibration.result', 'interrupted');
        Exit;
      end;
      if NowUs >= StartUs + AUDIO_CALIBRATION_DURATION_US then
      begin
        Active := false;
        Fit := Estimator.Estimate(ClockUncertaintyMs);
        Calibrated := Fit.Accepted;
        if Calibrated then Message := Reply(Index, 'audio.calibration.result', '')
        else Message := Reply(Index, 'audio.calibration.result', 'insufficient_confidence');
        Exit;
      end;
      Result := NowUs >= StartUs;
    end;
  finally LeaveCriticalSection(FLock); end;
end;

procedure TAudioCalibrationSessions.Observe(Index: integer; NowUs: int64;
  Tone: integer; Valid: boolean);
begin
  if (Index < 0) or (Index > High(FLanes)) then Exit;
  EnterCriticalSection(FLock);
  try
    if FLanes[Index].Active then FLanes[Index].Estimator.Observe(NowUs, Tone, Valid);
  finally LeaveCriticalSection(FLock); end;
end;

procedure TAudioCalibrationSessions.Cancel(Index: integer; const PlayerId, RequestId: UTF8String);
begin
  if (Index < 0) or (Index > High(FLanes)) then Exit;
  EnterCriticalSection(FLock);
  try
    if (FLanes[Index].RequestPlayer <> PlayerId) or (FLanes[Index].RequestId <> RequestId) then Exit;
    FLanes[Index].Pending := false;
    FLanes[Index].Active := false;
    FLanes[Index].Calibrated := false;
    FLanes[Index].LastRequestUs := 0; // A restarted input need not wait for the cancelled session's cooldown.
  finally LeaveCriticalSection(FLock); end;
end;

function TAudioCalibrationSessions.EffectivePlayerDelay(Index, GlobalDelayMs,
  ManualTrimMs: integer): integer;
var Delay: int64;
begin
  Result := ManualTrimMs;
  if (Index < 0) or (Index > High(FLanes)) then Exit;
  EnterCriticalSection(FLock);
  try
    if not FLanes[Index].Calibrated then Exit;
    // The beat clock already includes the global delay. Replace that baseline
    // for this calibrated input, then add the user's per-player trim exactly once.
    Delay := int64(FLanes[Index].Fit.DelayMs) - GlobalDelayMs + ManualTrimMs;
    Result := EnsureRange(Delay, int64(Low(integer)), int64(High(integer)));
  finally LeaveCriticalSection(FLock); end;
end;
end.
