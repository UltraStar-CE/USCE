unit UPhoneNoiseGate;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

interface

type
  TPhoneNoiseGate = record
  private
    Peaks: array[0..199] of Word;
    Histogram: array[0..100] of Word;
    Used, Cursor, PacketSamples, PacketPeak: integer;
  public
    procedure Reset;
    procedure Observe(Samples: PSmallInt; Count: integer);
    function Threshold(Manual: single): single;
  end;

implementation

uses Math;

procedure TPhoneNoiseGate.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

procedure TPhoneNoiseGate.Observe(Samples: PSmallInt; Count: integer);
var I, Bin: integer;
begin
  for I := 1 to Count do
  begin
    PacketPeak := Max(PacketPeak, Abs(integer(Samples^)));
    Inc(Samples);
    Inc(PacketSamples);
    if PacketSamples <> 480 then Continue;
    Bin := (PacketPeak * 100 + 32767) div 32768;
    if Used < Length(Peaks) then Inc(Used)
    else Dec(Histogram[Peaks[Cursor]]);
    Peaks[Cursor] := Bin;
    Inc(Histogram[Bin]);
    Cursor := (Cursor + 1) mod Length(Peaks);
    PacketSamples := 0;
    PacketPeak := 0;
  end;
end;

function TPhoneNoiseGate.Threshold(Manual: single): single;
var I, Seen: integer;
begin
  Result := Manual;
  if Used < 100 then Exit;
  Seen := 0;
  for I := Low(Histogram) to High(Histogram) do
  begin
    Inc(Seen, Histogram[I]);
    // Reject isolated transients while requiring headroom above steady noise.
    if Seen * 10 < Used * 9 then Continue;
    Result := Min(Manual, Max(0.02, I * 0.025));
    Exit;
  end;
end;

end.
