unit UFramePacer;

{ USCE frame pacing. GPL v2 or later; see LICENSE. }

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

type
  // One instance belongs to the rendering thread. No busy-waiting.
  TFramePacer = class
  private
    Frequency, Deadline, Period, Remainder, Fraction: UInt64;
    LastFPS: integer;
    {$IFDEF MSWINDOWS}
    Timer: NativeUInt;
    {$ENDIF}
    procedure Advance;
  protected
    function Clock: UInt64; virtual;
    procedure Wait(Milliseconds: double); virtual;
  public
    constructor Create(ClockFrequency: UInt64 = 0);
    destructor Destroy; override;
    procedure WaitForFrame(FPS: integer);
  end;

implementation

uses
  Math, SDL2
  {$IFDEF MSWINDOWS}, Windows{$ENDIF};

{$IFDEF MSWINDOWS}
type
  TCreateTimer = function(Attributes: pointer; Name: PWideChar;
    Flags, Access: DWORD): HANDLE; stdcall;
  TSetTimer = function(Handle: HANDLE; Due: PInt64; Period: longint;
    Callback, Data: pointer; Resume: BOOL): BOOL; stdcall;
var
  CreateTimer: TCreateTimer;
  SetTimer: TSetTimer;
{$ENDIF}

constructor TFramePacer.Create(ClockFrequency: UInt64);
begin
  inherited Create;
  Frequency := ClockFrequency;
  if Frequency = 0 then Frequency := SDL_GetPerformanceFrequency;
  {$IFDEF MSWINDOWS}
  // High-resolution timers are optional (Windows 10 1803+). Older systems
  // and failed allocations retain SDL's ordinary blocking delay.
  if Assigned(CreateTimer) and Assigned(SetTimer) then
    Timer := CreateTimer(nil, nil, 2, $00100002);
  {$ENDIF}
end;

destructor TFramePacer.Destroy;
begin
  {$IFDEF MSWINDOWS}
  if Timer <> 0 then CloseHandle(Timer);
  {$ENDIF}
  inherited;
end;

function TFramePacer.Clock: UInt64;
begin
  Result := SDL_GetPerformanceCounter;
end;

procedure TFramePacer.Wait(Milliseconds: double);
{$IFDEF MSWINDOWS}
var Due: Int64;
{$ENDIF}
begin
  if Milliseconds <= 0 then Exit;
  {$IFDEF MSWINDOWS}
  if Timer <> 0 then
  begin
    Due := -Max(Int64(1), Round(Milliseconds * 10000));
    if SetTimer(Timer, @Due, 0, nil, nil, false) and
       (WaitForSingleObject(Timer, Cardinal(Ceil(Milliseconds)) + 1000) = WAIT_OBJECT_0) then Exit;
    CloseHandle(Timer);
    Timer := 0;
  end;
  {$ENDIF}
  SDL_Delay(Cardinal(Ceil(Milliseconds)));
end;

procedure TFramePacer.Advance;
begin
  Deadline := Deadline + Period;
  Fraction := Fraction + Remainder;
  if Fraction >= UInt64(LastFPS) then
  begin
    Inc(Deadline);
    Fraction := Fraction - UInt64(LastFPS);
  end;
end;

procedure TFramePacer.WaitForFrame(FPS: integer);
var Now: UInt64;
begin
  FPS := Max(1, FPS);
  Now := Clock;
  if (FPS <> LastFPS) or (Deadline = 0) then
  begin
    LastFPS := FPS;
    Period := Max(UInt64(1), Frequency div UInt64(FPS));
    Remainder := Frequency mod UInt64(FPS);
    Fraction := 0;
    Deadline := Now;
    Advance;
  end;
  // Drop missed deadlines instead of submitting a burst of catch-up frames.
  if (Now > Deadline) and (Now - Deadline > Period) then
  begin
    Deadline := Now;
    Fraction := 0;
  end;
  if Deadline > Now then Wait((Deadline - Now) * 1000.0 / Frequency);
  Advance;
end;

{$IFDEF MSWINDOWS}
initialization
  CreateTimer := TCreateTimer(GetProcAddress(GetModuleHandle('kernel32.dll'), 'CreateWaitableTimerExW'));
  SetTimer := TSetTimer(GetProcAddress(GetModuleHandle('kernel32.dll'), 'SetWaitableTimer'));
{$ENDIF}
end.
