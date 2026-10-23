program TestVoiceParts;
{$MODE Delphi}
uses SysUtils, UVoiceParts;
var N, Columns, Rows, Voice: integer;
procedure Check(Condition: boolean);
begin
  if not Condition then Halt(1);
end;
begin
  Check(TryParseVoiceMarker('P1', Voice) and (Voice = 1));
  Check(TryParseVoiceMarker('P 24', Voice) and (Voice = 24));
  Check(TryParseVoiceMarker('P10', Voice) and (Voice = 10));
  Check(not TryParseVoiceMarker('P0', Voice));
  Check(not TryParseVoiceMarker('P-1', Voice));
  Check(not TryParseVoiceMarker('P1 text', Voice));
  Check(not TryParseVoiceMarker('P', Voice));
  Check(not TryParseVoiceMarker('P99999999999999999999', Voice));
  for N := 1 to 24 do
  begin
    GetVoiceGrid(N, Columns, Rows);
    Check((Columns > 0) and (Rows > 0) and (2 * Columns * Rows >= N));
    if N <= 4 then Check(Columns = 1);
  end;
  GetVoiceGrid(8, Columns, Rows);
  Check((Columns = 2) and (Rows = 2));
  GetVoiceGrid(12, Columns, Rows);
  Check((Columns = 3) and (Rows = 2));
  GetVoiceGrid(18, Columns, Rows);
  Check((Columns = 3) and (Rows = 3));
  WriteLn('Voice marker and layout tests passed');
end.
