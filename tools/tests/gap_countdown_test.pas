program gap_countdown_test;
{$MODE Delphi}
uses SysUtils, Math, UGapCountdown;
var G: TGapCountdown;
procedure Check(Now, MinimumGap, Expected: double; const Context: string);
begin
  if Abs(G.Remaining(Now, MinimumGap) - Expected) > 0.00001 then
    raise Exception.Create(Context);
end;
begin
  G := TGapCountdown.Create;
  try
    Check(0, 5, 0, 'empty chart');
    G.Add(20, 22); G.Add(0, 2); G.Prepare;
    Check(-1, 5, 0, 'intro uses existing count-in');
    Check(1, 5, 0, 'active note');
    Check(2, 5, 18, 'gap starts at preceding note end');
    Check(19.5, 5, 0.5, 'countdown reaches next note');
    Check(10, 20, 0, 'gap below threshold');
    Check(10, 18, 10, 'exact threshold');
    Check(10, 0, 0, 'off');
    Check(20, 5, 0, 'next note begins');
    Check(25, 5, 0, 'no trailing countdown');
    // A third voice fills what looks like a gap in the first two voices.
    G.Clear;
    G.Add(0, 2); G.Add(20, 22); G.Add(1, 12); G.Add(10, 21); G.Prepare;
    Check(15, 5, 0, 'third voice remains active');
    G.Clear;
    G.Add(0, 2); G.Add(7, 8); G.Add(7.5, 9); G.Add(7, 7); G.Prepare;
    Check(3, 5, 4, 'overlapping notes and exact five-second gap');
    Check(1, 5, 0, 'seek backwards into active note');
    Check(8, 5, 0, 'overlap extends active interval');
    WriteLn('PASS: gap thresholds, intro/outro, N-voice overlap and seeking');
  finally G.Free; end;
end.
