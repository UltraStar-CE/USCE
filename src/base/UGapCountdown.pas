unit UGapCountdown;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

interface

type
  TGapInterval = record
    StartTime, EndTime: double;
  end;
  TGapCountdown = class
  private
    Intervals: array of TGapInterval;
    Count: integer;
    procedure Sort(Left, Right: integer);
  public
    procedure Clear;
    procedure Add(StartTime, EndTime: double);
    procedure Prepare;
    function Remaining(Now, MinimumGap: double): double;
  end;

implementation

uses Math;

procedure TGapCountdown.Clear;
begin
  SetLength(Intervals, 0);
  Count := 0;
end;

procedure TGapCountdown.Add(StartTime, EndTime: double);
var I: integer;
begin
  if EndTime <= StartTime then Exit;
  I := Count;
  if Count = Length(Intervals) then SetLength(Intervals, Max(64, Count * 2));
  Inc(Count);
  Intervals[I].StartTime := StartTime;
  Intervals[I].EndTime := EndTime;
end;

procedure TGapCountdown.Sort(Left, Right: integer);
var I, J: integer; Pivot: double; Temp: TGapInterval;
begin
  I := Left; J := Right;
  Pivot := Intervals[(Left + Right) div 2].StartTime;
  repeat
    while Intervals[I].StartTime < Pivot do Inc(I);
    while Intervals[J].StartTime > Pivot do Dec(J);
    if I <= J then
    begin
      Temp := Intervals[I]; Intervals[I] := Intervals[J]; Intervals[J] := Temp;
      Inc(I); Dec(J);
    end;
  until I > J;
  if Left < J then Sort(Left, J);
  if I < Right then Sort(I, Right);
end;

procedure TGapCountdown.Prepare;
var I, Last: integer;
begin
  SetLength(Intervals, Count);
  if Count = 0 then Exit;
  Sort(0, High(Intervals));
  Last := 0;
  for I := 1 to High(Intervals) do
    if Intervals[I].StartTime <= Intervals[Last].EndTime then
      Intervals[Last].EndTime := Max(Intervals[Last].EndTime, Intervals[I].EndTime)
    else
    begin
      Inc(Last); Intervals[Last] := Intervals[I];
    end;
  Count := Last + 1;
  SetLength(Intervals, Count);
end;

function TGapCountdown.Remaining(Now, MinimumGap: double): double;
var Left, Right, Mid: integer;
begin
  Result := 0;
  if (MinimumGap <= 0) or (Length(Intervals) < 2) then Exit;
  Left := 0; Right := Length(Intervals);
  while Left < Right do
  begin
    Mid := (Left + Right) div 2;
    if Intervals[Mid].EndTime <= Now then Left := Mid + 1 else Right := Mid;
  end;
  // Intros use the existing count-in; there is no countdown after the last note.
  if (Left = 0) or (Left = Length(Intervals)) then Exit;
  if (Now < Intervals[Left].StartTime) and
     (Intervals[Left].StartTime - Intervals[Left-1].EndTime >= MinimumGap - 0.000001) then
    Result := Intervals[Left].StartTime - Now;
end;

end.
