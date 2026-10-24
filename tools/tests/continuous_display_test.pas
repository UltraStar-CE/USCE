program ContinuousDisplayTest;
{$mode delphi}{$R+}{$Q+}
uses SysUtils, UContinuousPlayback;
const
  SongLyrics: array[0..3] of boolean = (true, true, false, false);
  SongProgress: array[0..3] of boolean = (true, false, true, false);
  SingingNotes: array[0..4] of boolean = (true, true, true, false, false);
  SingingInfo: array[0..4] of boolean = (true, true, false, true, false);
  SingingFeedback: array[0..4] of boolean = (true, false, false, false, false);
var P, S, V: integer; D: TContinuousDisplay;
procedure Check(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;
begin
  for P := 0 to 1 do
    for S := 0 to 3 do
      for V := 0 to 4 do
      begin
        D := ContinuousDisplay(P = 1, S, V);
        Check(D.Lyrics = SongLyrics[S], 'Lyrics preset');
        Check(D.Progress = SongProgress[S], 'Progress preset');
        Check(D.Notes = ((P = 1) and SingingNotes[V]), 'Notes preset');
        Check(D.PlayerInfo = ((P = 1) and SingingInfo[V]), 'Player info preset');
        Check(D.Feedback = ((P = 1) and SingingFeedback[V]), 'Feedback preset');
      end;
  D := ContinuousDisplay(true, -1, 99);
  Check(D.Lyrics and D.Progress and D.Notes and D.PlayerInfo and D.Feedback,
    'Invalid values must preserve the full display');
  D := ContinuousDisplay(false, 2, 0);
  Check(D.Progress and not D.Lyrics and not D.Notes and not D.PlayerInfo and not D.Feedback,
    'Progress-only jukebox must have no singing overlays');
  Writeln('PASS: all 40 display combinations, invalid values and progress-only jukebox');
end.
