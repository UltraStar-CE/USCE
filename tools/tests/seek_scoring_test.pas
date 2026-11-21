program SeekScoringTest;
{$mode Delphi}
uses {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, IniFiles, UMusic, USong, UNote, UScreenSingController,
  UIni, URecord, UBeatTimer, UGraphic, UScreenName, UScreenSong, USingScores,
  UCommon, UParty, UThemes, UPath;
type TSeekScoringScreen = class(TScreenSingController);
var Screen: TSeekScoringScreen; Track, I: integer; Points, Before, Bonus: real;
  Loop: TPracticeLoop;

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
var Device: TAudioInputDevice; Sound: TCaptureBuffer; PerBeat: real; Color: TRGB;
  RatingBefore: real;

  procedure SetTestDelay(Delay: integer);
  var Config: TIniFile;
  begin
    Config := TIniFile.Create(Ini.FileName.ToNative);
    try
      // The legacy section loads on main and migrates on newer builds.
      Config.EraseSection('SlotDelay');
      Config.WriteInteger('PlayerDelay', 'P1', Delay);
    finally
      Config.Free;
    end;
    Ini.LastReadDelays := -1;
    Ini.ReloadDelays;
  end;

  procedure SingBeat(Beat: integer; Voiced: boolean; Seek: boolean);
  var J: integer;
  begin
    for J := 0 to High(Sound.AnalysisBuffer) do
      if Voiced then Sound.AnalysisBuffer[J] := Round(15000 * Sin(2 * Pi * 440 * J / 44100))
      else Sound.AnalysisBuffer[J] := 0;
    if Seek then
    begin
      Player[0].DetectionReady := false;
      SetLength(Player[0].SentenceEffectsShown, 0);
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
  Ini.Filename := Path(UTF8String(ParamStr(1))).Append('seek-delay.ini');
  SetLength(IPlayersVals, 1);
  IPlayersVals[0] := 1;
  Ini.Players := 0;
  LyricsState := TLyricsState(TLyricsState.NewInstance);
  ScreenSong := TScreenSong(TScreenSong.NewInstance);
  ScreenName := TScreenName(TScreenName.NewInstance);
  Party := TPartyGame(TPartyGame.NewInstance);
  Theme := TTheme(TTheme.NewInstance);
  Theme.Sing := TThemeSing.Create;
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
    Equal(Screen.Scores.Players[0].Score, MAX_SONG_SCORE - 1,
      'the target updates even when line bonus remains clamped at its maximum');
    // A line whose bonus was already updated during a retry still rates once.
    // Start below full so the meter cap cannot hide a duplicate adjustment.
    Screen.Scores.ClearPlayers;
    Screen.Scores.AddPlayer(nil, Color);
    Screen.Scores.SpawnPopUp(0, 0.5, Player[0].ScoreTotalInt);
    Screen.Scores.KillAllPopUps;
    RatingBefore := Screen.Scores.Players[0].RBTarget;
    Screen.OnSentenceEnd(0, 0, 0);
    Screen.OnSentenceEnd(0, 0, 0);
    Screen.Scores.Settings.Phase1Time := 0;
    Screen.Scores.Settings.Phase2Time := 0;
    Screen.Scores.Settings.Phase3Time := -1;
    Screen.Scores.Draw(false, false);
    Equal(Screen.Scores.Players[0].RBTarget, RatingBefore + 0.14,
      'a revised and already finalized line rates exactly once per pass');

    // A pre-existing score for a beat skipped by negative delay is replaced
    // by zero, while the following beat can still score from the new capture.
    SetTestDelay(-250);
    SingBeat(10, true, true);
    Equal(Player[0].Score, PerBeat, 'negative delay clears the unsampled prefix');
    SetTestDelay(0);

    Screen.Scores.ClearPlayers;
    Screen.Scores.AddPlayer(nil, Color);
    Screen.Scores.AddPlayer(nil, Color);
    Screen.Scores.SpawnPopUp(0, 0.73, 1000);
    Screen.Scores.SpawnPopUp(1, 0.93, 2000);
    Equal(Screen.Scores.Players[0].RBPos, 0.73, 'the first line immediately fills the meter to 73%');
    Equal(Screen.Scores.Players[1].RBPos, 0.93, 'each singer gets their own first-line percentage');
    Screen.Scores.SpawnPopUp(0, 0.75, 500);
    Screens := 1;
    ScreenAct := 1;
    Screen.Scores.Init;
    RatingBefore := Screen.Scores.Players[0].RBTarget;
    Screen.Scores.Settings.Phase1Time := -1;
    Screen.Scores.Settings.Phase3Time := High(integer);
    Screen.Scores.Draw(false, false);
    Equal(Screen.Scores.Players[0].RBTarget, RatingBefore,
      'a lower score does not reset the rating during the popup');
    Equal(Screen.Scores.Players[0].Score, 500, 'downward revision sets the new target');
    Equal(Screen.Scores.Players[1].Score, 2000, 'other singer popup is preserved');
    Screen.Scores.SetScore(0, 400);
    Equal(Screen.Scores.Players[0].RBTarget, RatingBefore, 'a revision keeps both ratings pending');
    Screen.Scores.Settings.Phase1Time := 0;
    Screen.Scores.Settings.Phase2Time := 0;
    Screen.Scores.Settings.Phase3Time := -1;
    Screen.Scores.Draw(false, false);
    Equal(Screen.Scores.Players[0].ScoreDisplayed, 400, 'revised display cannot restore old popup points');
    Equal(Screen.Scores.Players[0].RBTarget, RatingBefore + 0.04,
      'the later rating finishes after a downward revision');
    Equal(Screen.Scores.Players[1].RBTarget, 0.93, 'the first rating stays exact after its popup exits');
    Equal(Screen.Scores.Players[1].ScoreDisplayed, 2000, 'other singer points finish');
    Player[0].ResetScores;
    Check(GetPlayerSentenceScore(0, 0, 0, PerBeat), 'initialize loop scoring');
    Player[0].ReplaceBeatScore(0, 0, 9, 25, false);
    Player[0].ReplaceBeatScore(0, 0, 10, 100, false);
    Player[0].ReplaceBeatScore(0, 0, 11, 200, false);
    Player[0].ReplaceBeatScore(0, 0, 12, 50, false);
    Screen.PracticeLoop.SelectPoint(GetTimeFromBeat(10));
    Screen.PracticeLoop.SelectPoint(GetTimeFromBeat(12));
    Player[0].DetectionReady := true;
    Player[0].DetectionBeat := 10;
    FinishPracticePassScoring(Screen);
    Equal(Player[0].Score, 175, 'unsampled loop tail clears old points; both outside beats survive');
    Check(Player[0].SentenceFinalized[0][0], 'a line ending exactly at B still awards its revised bonus');
    Screen.PracticeLoop := Default(TPracticeLoop);
    Screen.PracticeLoop.SelectPoint(GetTimeFromBeat(10));
    Screen.PracticeLoop.SelectPoint(GetTimeFromBeat(29) + 0.3 * 60 / CurrentSong.BPM);
    CurrentSong.Tracks[0].Lines[0].Notes[0].Duration := 20;
    Player[0].DetectionDelay := 0;
    Player[0].DetectionBeat := 28;
    Check(Screen.LastPracticeBeat = 29, 'fractional B keeps its last beat');
    Check(Screen.HasPendingDelayedScoring(Screen.LastPracticeBeat, true),
      'practice waits for the last beat midpoint at zero delay');
    Check(not Screen.HasPendingDelayedScoring(Screen.LastPracticeBeat),
      'ordinary end still ignores an undelayed cursor without a pending capture window');
    Player[0].LocalCaptureWindowPending := true;
    Check(Screen.HasPendingDelayedScoring(Screen.LastPracticeBeat),
      'the scoring tail waits for the final local window even at zero delay');
    Player[0].DetectionBeat := 29;
    Check(not Screen.HasPendingDelayedScoring(Screen.LastPracticeBeat),
      'a capture window cannot extend scoring beyond the song or loop boundary');
    ResetSungPitchReference;
    Check(not Player[0].LocalCaptureWindowPending, 'a seek clears the pending local window');
    Check(not Screen.HasPendingDelayedScoring(Screen.LastPracticeBeat, true),
      'practice wraps once the last beat is sampled');
    Screen.PracticeLoop := Default(TPracticeLoop);
    WriteLn('Real PCM hit/miss retries and pending score display passed');
  finally
    Screen.Scores.Free; Screen.Scores := nil;
    Device.AudioFormat.Free; Device.FreeInstance;
    Theme.Sing.Free;
    Theme.FreeInstance; Theme := nil;
    Party.FreeInstance; Party := nil;
    ScreenName.FreeInstance; ScreenName := nil;
    ScreenSong.FreeInstance; ScreenSong := nil;
    LyricsState.FreeInstance; LyricsState := nil;
    Ini.Filename := nil;
    Ini.FreeInstance; Ini := nil;
    IPlayersVals := nil;
  end;
end;

begin
  Loop := Default(TPracticeLoop);
  Loop.SelectPoint(12);
  Check(Loop.HasStart and not Loop.HasEnd, 'first click sets only a start');
  Check(not Loop.ReachedEnd(99, true), 'no seek with only a start');
  Loop.SelectPoint(12);
  Check(not Loop.HasEnd, 'repeating a point does not create a zero-length loop');
  Loop.SelectPoint(8);
  Check(Loop.HasEnd, 'second distinct click completes the loop');
  Equal(Loop.StartTime, 8, 'reverse selection uses the earlier point as start');
  Equal(Loop.EndTime, 12, 'reverse selection uses the later point as end');
  Check(not Loop.ReachedEnd(11.99, false), 'loop waits for its end');
  Check(Loop.ReachedEnd(12, false), 'loop wraps at its end');
  Check(Loop.ReachedEnd(11.99, true), 'a loop ending at the file boundary wraps on EOF');
  Loop.SelectPoint(10);
  Check(not Loop.HasStart and not Loop.HasEnd, 'third click clears the loop');
  Loop.SelectPoint(11);
  Equal(Loop.StartTime, 11, 'next click starts another loop');

  CurrentSong := TSong.Create;
  SetLength(CurrentSong.Tracks, 8);
  CurrentSong.isDuet := true;
  // Exercise the real bonus calculation without creating a window or textures.
  Screen := TSeekScoringScreen(TSeekScoringScreen.NewInstance);
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
