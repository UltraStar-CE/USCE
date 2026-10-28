program SongCompletionTest;
{$mode Delphi}
uses Classes, SysUtils, UMusic, USong, UNote, UPath, ULog;

var Song: TSong; ChartFile: TextFile; I: integer; Chart: string;

procedure Check(Value: boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure LoadChart(const Notes: string; Voices: integer = 1);
begin
  FreeAndNil(Song);
  AssignFile(ChartFile, IncludeTrailingPathDelimiter(ParamStr(1)) + 'completion.txt');
  Rewrite(ChartFile);
  Write(ChartFile, Notes, 'E', LineEnding);
  CloseFile(ChartFile);
  Song := TSong.Create;
  Song.Path := Path(UTF8String(ParamStr(1)));
  Song.FileName := Path('completion.txt');
  Song.VoiceCount := Voices;
  Song.BPM := 240;
  Check(Song.LoadSong(false), 'load completion fixture: ' + Song.LastError);
end;

procedure CheckLastLine(Track: integer);
var L: integer;
begin
  for L := 0 to High(Song.Tracks[Track].Lines) do
    Check(Song.Tracks[Track].Lines[L].LastLine = (L = High(Song.Tracks[Track].Lines)),
      'only the actual final lyric line fades');
end;

begin
  Log := TLog.Create;
  ScoreFactor := StandardScoreFactor;
  LoadChart(': 0 4 60 sung' + LineEnding + '- 8' + LineEnding +
    'F 8 8 60 freestyle' + LineEnding);
  Check(Song.Tracks[0].HighestScoredBeat = 4, 'freestyle tail does not delay completion');
  CheckLastLine(0);

  Chart := '';
  for I := 1 to 8 do
    Chart := Chart + 'P' + IntToStr(I) + LineEnding +
      ': 0 ' + IntToStr(I * 4) + ' 60 sung' + LineEnding + '- 40' + LineEnding +
      'F 40 8 60 tail' + LineEnding;
  LoadChart(Chart, 8);
  for I := 0 to 7 do
  begin
    Check(Song.Tracks[I].HighestScoredBeat = (I + 1) * 4, 'independent N-voice boundary');
    CheckLastLine(I);
  end;

  ScoreFactor[ntNormal] := 0;
  LoadChart('R 0 4 60 rap' + LineEnding + '- 8' + LineEnding + ': 8 8 60 zero weight' + LineEnding);
  Check(Song.Tracks[0].HighestScoredBeat = 4, 'zero-weight tail does not delay completion');
  CheckLastLine(0);
  ScoreFactor := StandardScoreFactor;
  ScoreFactor[ntFreestyle] := 100;
  LoadChart('F 0 8 60 weighted freestyle' + LineEnding);
  Check(Song.Tracks[0].HighestScoredBeat = 8, 'positive freestyle weight can score');

  ScoreFactor := StandardScoreFactor;
  LoadChart('F 0 8 60 no score' + LineEnding);
  Check(Song.Tracks[0].HighestScoredBeat = Low(Integer), 'no scored notes has no time boundary');
  CheckLastLine(0);
  LoadChart(': -16 4 60 negative beat' + LineEnding);
  Check(Song.Tracks[0].HighestScoredBeat = -12, 'negative scoring boundary is retained');
  LoadChart(': 0 40 60 long note' + LineEnding + '- 8' + LineEnding + ': 8 4 60 short note' + LineEnding);
  Check(Song.Tracks[0].HighestScoredBeat = 40, 'earlier overlapping line can finish last');

  LoadChart(': 0 4 60 before' + LineEnding + '- 8' + LineEnding +
    ': 8 4 60 inside' + LineEnding + '- 16' + LineEnding +
    ': 16 4 60 outside' + LineEnding);
  Song.Medley.StartBeat := 8;
  Song.Medley.EndBeat := 16;
  Song.SetMedleyMode;
  Check(Song.Tracks[0].HighestScoredBeat = 12, 'medley rebuilds its scoring boundary');
  Check(Song.Tracks[0].Lines[0].Notes[0].ScoreExcluded, 'medley excludes earlier notes');
  CheckLastLine(0);

  Song.Free;
  CurrentSong := nil;
  Log.Free;
  Log := nil;
  WriteLn('PASS: lyric endings, eight voices, scoring weights, excluded notes, negative beats and medleys');
end.
