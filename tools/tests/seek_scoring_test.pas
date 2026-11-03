program SeekScoringTest;
{$mode Delphi}
uses SysUtils, Math, UMusic, USong, UNote, UScreenSingController,
  UIni, URecord, UBeatTimer, UGraphic, UScreenSong, USingScores, UCommon;
var Screen: TScreenSingController; Track, I: integer; Points, Before, Bonus: real;

procedure Check(Value: boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure Equal(Actual, Expected: real; const MessageText: string);
begin
  Check(Abs(Actual - Expected) < 0.000001, MessageText + ': ' + FloatToStr(Actual) + ' expected ' + FloatToStr(Expected));
end;

procedure FinalizeLine(Track, LineIndex: integer);
begin
  Screen.OnSentenceEnd(Track, LineIndex, 0, false);
end;

procedure CheckMicrophoneRetries;
var Device: TAudioInputDevice; Sound: TCaptureBuffer; I: integer; PerBeat: real; Color: TRGB;

  procedure SingBeat(Beat: integer; Voiced: boolean; Seek: boolean);
  var J: integer;
  begin
    for J := 0 to High(Sound.AnalysisBuffer) do
      if Voiced then Sound.AnalysisBuffer[J] := Round(15000 * Sin(2 * Pi * 440 * J / 44100))
      else Sound.AnalysisBuffer[J] := 0;
    if Seek then
    begin
      Player[0].DetectionReady := false;
      Player[0].HighNote := -1;
      Player[0].LengthNote := 0;
      SetLength(Player[0].Note, 0);
    end;
    LyricsState.MidBeatD := Beat;
    LyricsState.CurrentBeatD := Beat;
    NewNote(0, Screen);
  end;

begin
  Ini := TIni(TIni.NewInstance);
  LyricsState := TLyricsState(TLyricsState.NewInstance);
  ScreenSong := TScreenSong(TScreenSong.NewInstance);
  ScreenSong.Mode := smNormal;
  ScoreFactor := StandardScoreFactor;
  Device := TAudioInputDevice(TAudioInputDevice.NewInstance);
  Device.AudioFormat := TAudioFormatInfo.Create(1, 44100, asfS16);
  SetLength(Device.CaptureChannel, 1);
  Sound := AudioInputProcessor.Sound[0];
  Device.LinkCaptureBuffer(0, Sound);
  Screen.Scores := TSingScores.Create;
  Color := Default(TRGB);
  Screen.Scores.AddPlayer(nil, Color);
  Screen.Scores.AddPlayer(nil, Color);
  try
    PlayersPlay := 1;
    Player[0].ResetScores;
    Player[0].Track := 0;
    Player[0].Level := 2;
    CurrentSong.BPM := 240;
    CurrentSong.isDuet := false;
    Screen.NumEmptySentences[0] := 0;
    SetLength(CurrentSong.Tracks, 1);
    CurrentSong.Tracks[0].High := 0;
    CurrentSong.Tracks[0].ScoreValue := 2 * ScoreFactor[ntNormal];
    SetLength(CurrentSong.Tracks[0].Lines, 1);
    with CurrentSong.Tracks[0].Lines[0] do
    begin
      HighNote := 0; ScoreValue := 2 * ScoreFactor[ntNormal];
      SetLength(Notes, 1);
      Notes[0].StartBeat := 10; Notes[0].Duration := 2;
      Notes[0].Tone := 9; Notes[0].DisplayTone := 9; Notes[0].NoteType := ntNormal;
    end;
    PerBeat := (MAX_SONG_SCORE - MAX_SONG_LINE_BONUS) / 2;
    SingBeat(10, true, true);
    Equal(Player[0].Score, PerBeat, 'real microphone detector scores the first beat');
    SingBeat(11, true, false);
    Equal(Player[0].Score, PerBeat * 2, 'normal playback scores the next beat');
    SingBeat(10, false, true);
    Equal(Player[0].Score, PerBeat, 'silent retry replaces a hit through NewNote');
    SingBeat(10, true, true);
    Equal(Player[0].Score, PerBeat * 2, 'voiced retry restores only that beat');
    SingBeat(10, true, true);
    Equal(Player[0].Score, PerBeat * 2, 'repeated input cannot inflate the score');
    SingBeat(11, true, false);
    SingBeat(12, false, false);
    Equal(Player[0].ScoreTotalInt, MAX_SONG_SCORE, 'complete line receives its bonus');
    Equal(Player[0].ScorePerfectRemaining, 0, 'first pass consumes all score potential');
    SingBeat(10, false, true);
    Equal(Player[0].Score, PerBeat, 'partial-line retry preserves the untouched second beat');
    Check(Player[0].ScoreLine < MAX_SONG_LINE_BONUS, 'real retry revises an awarded line bonus');
    SingBeat(10, true, true);
    Equal(Player[0].ScoreTotalInt, MAX_SONG_SCORE, 'restored hit restores its line bonus without inflation');
    Equal(Player[0].ScorePerfectRemaining, 0, 'retries cannot consume score potential again');
    Player[0].ReplaceBeatScore(0, 0, 10, PerBeat - 1, false);
    FinalizeLine(0, 0);
    Equal(Screen.Scores.Players[0].ScoreDisplayed, MAX_SONG_SCORE - 1,
      'display updates even when line bonus remains clamped at its maximum');
    Screen.Scores.ClearPlayers;
    Screen.Scores.AddPlayer(nil, Color);
    Screen.Scores.AddPlayer(nil, Color);
    Screen.Scores.SpawnPopUp(0, 8, 1000);
    Screen.Scores.SpawnPopUp(1, 8, 2000);
    Screen.Scores.SetScore(0, 500);
    Equal(Screen.Scores.Players[0].ScoreDisplayed, 500, 'revised display discards obsolete animated points');
    Equal(Screen.Scores.Players[1].Score, 2000, 'other singer popup is preserved');
    Screen.Scores.KillAllPopUps;
    Screen.Scores.SetScore(0, 400);
    Equal(Screen.Scores.Players[0].ScoreDisplayed, 400, 'revised display cannot restore old popup points');
    WriteLn('Real PCM hit/miss retries and pending score display passed');
  finally
    Screen.Scores.Free; Screen.Scores := nil;
    Device.AudioFormat.Free; Device.FreeInstance;
    ScreenSong.FreeInstance; ScreenSong := nil;
    LyricsState.FreeInstance; LyricsState := nil;
    Ini.FreeInstance; Ini := nil;
  end;
end;

begin
  CurrentSong := TSong.Create;
  SetLength(CurrentSong.Tracks, 8);
  CurrentSong.isDuet := true;
  // Exercise the real bonus calculation without creating a window or textures.
  Screen := TScreenSingController(TScreenSingController.NewInstance);
  SetLength(Screen.NumEmptySentences, 8);
  SetLength(Player, 2);
  PlayersPlay := 2;
  for Track := 0 to 7 do
  begin
    CurrentSong.Tracks[Track].High := 2;
    CurrentSong.Tracks[Track].ScoreValue := 8;
    SetLength(CurrentSong.Tracks[Track].Lines, 3);
    CurrentSong.Tracks[Track].Lines[0].ScoreValue := 4;
    CurrentSong.Tracks[Track].Lines[1].ScoreValue := 4;
    Screen.NumEmptySentences[Track] := 1; // non-scoring freestyle tail
  end;
  try
    for Track := 0 to 7 do
    begin
      for I := 0 to 1 do Player[I].ResetScores;
      Player[0].Track := Track;
      Player[0].Level := Track mod 3;
      Check(GetPlayerSentenceScore(0, Track, 0, Points), 'initialize score history');
      Check(GetPlayerSentenceScore(1, Track, 0, Points), 'initialize second player');
      // Seek forward into a later line, then return to an earlier line.
      Player[0].ReplaceBeatScore(Track, 1, 20, 200, true);
      Player[0].ReplaceBeatScore(Track, 0, 10, 100, false);
      Player[0].ReplaceBeatScore(Track, 0, 11, 150, false);
      FinalizeLine(Track, 0);
      Bonus := Player[0].SentenceBonus[Track][0];
      Before := Player[0].ScoreTotalInt;
      for I := 1 to 100 do
        Player[0].ReplaceBeatScore(Track, 0, 10, 100, false);
      FinalizeLine(Track, 0);
      Equal(Player[0].ScoreTotalInt, Before, 'retries cannot accumulate note or line points');
      // A missed beat replaces its previous hit; untouched beats and golden points survive.
      Player[0].ReplaceBeatScore(Track, 0, 10, 0, false);
      FinalizeLine(Track, 0);
      Equal(Player[0].Score, 150, 'only the replayed beat loses points');
      Equal(Player[0].ScoreGolden, 200, 'another line retains its golden points');
      Check(Player[0].SentenceBonus[Track][0] < Bonus, 'bonus follows revised performance');
      Player[0].ReplaceBeatScore(Track, 0, 10, 50, false);
      FinalizeLine(Track, 0);
      Equal(Player[0].SentenceScore[Track][0], 200, 'partial retry preserves untouched part of line');
      Bonus := Player[0].ScoreLine;
      FinalizeLine(Track, 2);
      Equal(Player[0].ScoreLine, Bonus, 'freestyle tail adds no bonus');
      // Identical beats in different voices and players remain independent.
      Player[1].ReplaceBeatScore(Track, 0, 10, 75, false);
      Equal(Player[0].Score, 200, 'another player cannot change this score');
      Equal(Player[1].Score, 75, 'second player owns a separate history');
      Check(Player[0].ConsumeBeatPotential(Track, 10, false), 'first note potential consumed');
      Check(not Player[0].ConsumeBeatPotential(Track, 10, false), 'retry cannot consume potential twice');
      Check(Player[0].ConsumeBeatPotential(Track, 10, true), 'line potential is separate');
      Check(not Player[0].ConsumeBeatPotential(Track, 10, true), 'line potential counted once');
      Check(Player[0].ConsumeBeatPotential((Track + 1) mod 8, 10, false), 'voice histories are separate');
      Player[0].ResetScores;
      Equal(Player[0].ScoreTotalInt, 0, 'explicit restart clears points');
      Check(Length(Player[0].ScoredBeats) = 0, 'explicit restart clears retry history');
      Check(Player[0].ConsumeBeatPotential(Track, 10, false), 'restart restores potential');
    end;
    CheckMicrophoneRetries;
    WriteLn('Seek score replacement, partial retries, bonuses, freestyle tails and 8 voices passed');
  finally
    Screen.FreeInstance;
    FreeAndNil(CurrentSong);
    SetLength(Player, 0);
  end;
end.
