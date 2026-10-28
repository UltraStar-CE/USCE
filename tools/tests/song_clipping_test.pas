program SongClippingTest;
{$mode Delphi}
uses Classes, SysUtils, UMusic, USong, UNote, UPath, ULog, UIni;
var Song: TSong; ChartFile: TextFile;

procedure Check(Value: boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure LoadChart(const Notes, Headers: string; AudioLength: real; Clip: boolean = true);
begin
  FreeAndNil(Song);
  AssignFile(ChartFile, IncludeTrailingPathDelimiter(ParamStr(1)) + 'clipping.txt');
  Rewrite(ChartFile);
  Write(ChartFile, '#TITLE:Clipping', LineEnding, '#ARTIST:Test', LineEnding,
    '#MP3:audio.wav', LineEnding, '#BPM:60', LineEnding, Headers, Notes, 'E', LineEnding);
  CloseFile(ChartFile);
  Song := TSong.Create;
  Song.Mult := 1;
  Song.Path := Path(UTF8String(ParamStr(1)));
  Song.FileName := Path('clipping.txt');
  Check(Song.Analyse(false, false, Clip, AudioLength, true), 'load clipping fixture: ' + Song.LastError);
end;

procedure CheckNote(LineIndex, NoteIndex: integer; Excluded: boolean);
begin
  Check(Song.Tracks[0].Lines[LineIndex].Notes[NoteIndex].ScoreExcluded = Excluded,
    'clipping must use absolute start and duration, not pitch');
end;

begin
  Log := TLog.Create;

  Ini := TIni.Create;
  ScoreFactor := StandardScoreFactor;
  with TFileStream.Create(IncludeTrailingPathDelimiter(ParamStr(1)) + 'audio.wav', fmCreate) do Free;
  LoadChart(': 0 4 0 low' + LineEnding + ': 4 4 60 high' + LineEnding,
    '', 12);
  CheckNote(0, 0, false);
  CheckNote(0, 1, false);
  Check(Song.Tracks[0].HighestScoredBeat = 8, 'in-bounds high pitch still scores');

  LoadChart(': 44 3 60 before' + LineEnding + ': 44 4 0 exact' + LineEnding +
    ': 44 5 0 beyond' + LineEnding, '', 12);
  CheckNote(0, 0, false);
  CheckNote(0, 1, true); // Preserve the existing exclusive audio-end boundary.
  CheckNote(0, 2, true);

  LoadChart(': 0 4 60 before start' + LineEnding + ': 8 4 60 at start' + LineEnding,
    '#START:2' + LineEnding, 12);
  CheckNote(0, 0, true);
  CheckNote(0, 1, false);

  LoadChart(': 0 4 60 shifted' + LineEnding, '#GAP:11000' + LineEnding, 12);
  CheckNote(0, 0, true);
  LoadChart(': 0 4 60 shifted' + LineEnding, '#GAP:10000' + LineEnding, 12);
  CheckNote(0, 0, false);

  LoadChart(': 0 4 60 first' + LineEnding + '- 8 40' + LineEnding +
    ': 0 4 60 inside' + LineEnding + ': 8 4 0 outside' + LineEnding,
    '#RELATIVE:YES' + LineEnding, 12);
  Check(Song.Tracks[0].Lines[1].Notes[0].StartBeat = 40, 'relative start is normalized');
  CheckNote(1, 0, false);
  CheckNote(1, 1, true);

  LoadChart(': 0 4 60 first' + LineEnding + '- 8 40' + LineEnding +
    ': 0 4 60 inside' + LineEnding, '#RELATIVE:YES' + LineEnding +
    '#START:10' + LineEnding, 12);
  CheckNote(0, 0, true);
  CheckNote(1, 0, false);

  ScoreFactor[ntFreestyle] := 100;
  LoadChart(': 0 4 60 inside' + LineEnding + ': 48 4 0 outside' + LineEnding, '', 12);
  CheckNote(0, 1, true);
  Check(Song.Tracks[0].HighestScoredBeat = 4, 'positive freestyle weight cannot restore clipped notes');
  LoadChart(': 48 4 60 outside' + LineEnding, '', 12, false);
  CheckNote(0, 0, false);
  LoadChart(': 48 4 60 unknown length' + LineEnding, '', 0);
  CheckNote(0, 0, false);

  Ini.Free;
  Ini := nil;
  Song.Free;
  CurrentSong := nil;
  Log.Free;
  Log := nil;
  WriteLn('PASS: duration/pitch, audio boundaries, START/GAP, relative notes and weighted freestyle clipping');
end.
