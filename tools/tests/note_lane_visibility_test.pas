program NoteLaneVisibilityTest;
{$mode Delphi}

uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils, UMusic, UDraw;

const
  InternalBPM = 600; // #BPM:150 stores four chart beats per musical beat.

var
  Track: TLines;

procedure AddNote(Line, Beat, Duration: integer; NoteType: TNoteType = ntNormal);
var
  I: integer;
begin
  I := Length(Track.Lines[Line].Notes);
  SetLength(Track.Lines[Line].Notes, I + 1);
  Track.Lines[Line].HighNote := I;
  Track.Lines[Line].Notes[I].StartBeat := Beat;
  Track.Lines[Line].Notes[I].Duration := Duration;
  Track.Lines[Line].Notes[I].NoteType := NoteType;
end;

procedure Expect(CurrentLine: integer; Beat, BPM: real; Expected: integer;
  const MessageText: string; ShowFreestyle: boolean = true);
var
  Actual: integer;
begin
  Track.CurrentLine := CurrentLine;
  Actual := GetVisibleNoteLine(Track, Beat, BPM, ShowFreestyle);
  if Actual <> Expected then
    raise Exception.CreateFmt('%s: expected line %d at beat %g, got %d',
      [MessageText, Expected, Beat, Actual]);
end;

begin
  SetLength(Track.Lines, 6);
  Track.High := High(Track.Lines);
  AddNote(0, 100, 41);
  AddNote(1, 199, 18);
  AddNote(2, 267, 30, ntGolden);
  AddNote(3, 397, 15);
  AddNote(3, 502, 20);
  Track.Lines[4].HighNote := -1;
  AddNote(5, 620, 10, ntFreestyle);

  Expect(0, 59, InternalBPM, -1, 'intro before preview is empty');
  Expect(0, 60, InternalBPM, 0, 'first notes appear during preview');
  Expect(0, 157, InternalBPM, 0, 'three-beat hidden interval would blink before the break');
  Expect(1, 157, InternalBPM, 1, 'the same short gap after the break stays visible');
  Expect(2, 219, InternalBPM, 2, 'early break in the 50-beat pause keeps the lane visible');
  Expect(1, 225, InternalBPM, 1, 'late break keeps the previous line visible during its hold');
  Expect(1, 227, InternalBPM, 2, 'preview selects the next line from actual note time');
  Expect(2, 311, InternalBPM, 2, 'golden line stays visible through its hold');
  Expect(2, 312, InternalBPM, -1, 'long gap hides the lane after the hold');
  Expect(2, 356, InternalBPM, -1, 'lane stays hidden until the following preview');
  Expect(2, 357, InternalBPM, 3, 'late break previews new notes without old golden notes');
  Expect(3, 440, InternalBPM, -1, 'long pause within a line hides the lane');
  Expect(3, 462, InternalBPM, 3, 'preview resumes within the same line');
  Expect(3, 580, InternalBPM, 5, 'preview can skip an empty lyric line');
  Expect(4, 580, InternalBPM, -1, 'fully hidden freestyle does not show a lane', false);
  Expect(5, 645, InternalBPM, -1, 'outro is empty once hold ends');

  // At a slower tempo the same three chart beats last one second.
  Expect(0, 157, 180, -1, 'one-second blank between hold and preview can be hidden');
  WriteLn('PASS: note lanes follow actual notes across early and late breaks, avoid blinks, and hide in long gaps');
end.
