{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL$
 * $Id$
 *}

unit UNote;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  SysUtils,
  Classes,
  sdl2,
  UDisplay,
  UIni,
  ULog,
  ULyrics,
  UMusic,
  URecord,
  UScreenSingController,
  USong,
  UTime;

type
  PPLayerNote = ^TPlayerNote;
  TPlayerNote = record
    Start:    integer;
    Duration: integer;
    Detect:   real;    // accurate place, detected in the note
    Tone:     real;
    Perfect:  boolean; // true if the note matches the original one, light the star
    Hit:      boolean; // true if the note hits the line
    NoteType: TNoteType;
  end;

  PPLayer = ^TPlayer;
  TPlayer = record
  private
    _Score:       real;
    _ScoreLine:   real;
    _ScoreGolden: real;
    _ScoreInt:       integer;
    _ScoreLineInt:   integer;
    _ScoreGoldenInt: integer;
    _ScoreTotalInt:  integer;
    procedure SetScore(newScore: real);
    procedure SetScoreLine(newScoreLine: real);
    procedure SetScoreGolden(newScoreGolden: real);
    procedure UpdateIntScores;

  public
    Name:           UTF8String;
    Level:          integer; // 0 - easy, 1 - medium, 2 - hard
    Track:          integer; // 0 - track 1, 1 - track 2 (duet)

    // Index in Teaminfo record
    TeamID:         byte;
    PlayerID:       byte;

    ScorePerfectRemaining: real;

    // LineBonus
    DetectionBeat: integer;
    DetectionReady: boolean;
    DetectionDelay: integer;
    ScoreLast:      real;    // Last Line Score

    // PerfectLineTwinkle (effect)
    LastSentencePerfect: boolean;

    HighNote:       integer; // index of last note (= High(Note)?)
    LengthNote:     integer; // number of notes (= Length(Note)?).
    Note:           array of TPlayerNote;
    SentenceScore:  array of array of real;

    // Scores
    property Score:       real read _Score write SetScore;
    property ScoreLine:   real read _ScoreLine write SetScoreLine;
    property ScoreGolden: real read _ScoreGolden write SetScoreGolden;

    property ScoreInt:       integer read _ScoreInt;
    property ScoreLineInt:   integer read _ScoreLineInt;
    property ScoreGoldenInt: integer read _ScoreGoldenInt;
    property ScoreTotalInt:  integer read _ScoreTotalInt;
    procedure ResetScores;
  end;

  TStats = record
    Player: array of TPlayer;
    SongArtist:   String;
    SongTitle:    String;
  end;

  TMedleyPlaylist = record
    Song:               array of integer;
    NumMedleySongs:     integer;
    CurrentMedleySong:  integer;
    ApplausePlayed:     boolean;
    Stats:              array of TStats;
    NumPlayer:          integer;
  end;

{* Player and music info *}
var
  {**
   * Player info and state for each player.
   * The amount of players is given by PlayersPlay.
   *}
  Player: array of TPlayer;

  {**
   * Number of players or teams playing.
   * Possible values: 1 - 6
   *}
  PlayersPlay: integer;

  {**
   * Selected song for singing.
   *}
  CurrentSong: TSong;

  PlaylistMedley: TMedleyPlaylist;  // playlist medley

const
  MAX_SONG_SCORE = 10000;     // max. achievable points per song
  MAX_SONG_LINE_BONUS = 1000; // max. achievable line bonus per song
  REMOTE_INPUT_LATE_BEAT_WINDOW = 8;

procedure Sing(Screen: TScreenSingController);
procedure NewSentence(CP: integer; Screen: TScreenSingController);
procedure NewBeatClick(Screen: TScreenSingController);  // executed when on then new beat for click
procedure StopSingClicks;
procedure NewBeatDetect(Screen: TScreenSingController); // executed when on then new beat for detection
procedure NewNote(CP: integer; Screen: TScreenSingController);       // detect note
function  GetMidBeat(Time: real): real;
function  GetTimeFromBeat(Beat: integer; SelfSong: TSong = nil): real;
function  GetPlayerSentenceScore(PlayerIndex, Track, SentenceIndex: integer; out Points: real): boolean;

implementation

uses
  UPhoneAudio,
  Math,
  StrUtils,
  UCatCovers,
  UCommandLine,
  UCommon,
  UConfig,
  UDataBase,
  UGraphic,
  UGraphicClasses,
  UJoystick,
  ULanguage,
  MidiOut,
  UParty,
  UPathUtils,
  UPlatform,
  UPlaylist,
  URemoteInput,
  USkins,
  USongs,
  UThemes;

type
  TSingClickClock = class(TSyncSource)
    Origin: real;
    function GetClock: real; override;
  end;

var
  BeatClickOutput: TMidiOutput = nil;
  BeatClickClock: TSingClickClock = nil;
  BeatClickScheduled: boolean = false;

function TSingClickClock.GetClock: real;
begin
  Result := AudioPlayback.Position - Origin;
end;

procedure StopSingClicks;
begin
  if Assigned(BeatClickOutput) then BeatClickOutput.Stop;
  BeatClickScheduled := false;
end;

procedure TPlayer.SetScore(newScore: real);
begin
  _Score := newScore;
  UpdateIntScores;
end;
procedure TPlayer.SetScoreLine(newScoreLine: real);
begin
  _ScoreLine := newScoreLine;
  UpdateIntScores;
end;
procedure TPlayer.SetScoreGolden(newScoreGolden: real);
begin
  _ScoreGolden := newScoreGolden;
  UpdateIntScores;
end;
procedure TPlayer.UpdateIntScores();
begin
  // total score
  _ScoreTotalInt := round(Score + ScoreGolden + ScoreLine);
  // components
  _ScoreInt := round(Score);
  _ScoreGoldenInt := round(ScoreGolden);
  _ScoreLineInt := round(ScoreLine);
  // _ScoreTotalInt = as close to the truth as possible, but the components might not add up to it
  // this can happen if:
  // * all the components are .2 (total is one higher than sum of components)
  // * all the components are .6 (total is one less than the sum of components)
  // in these cases we just +1/-1 a component so that it fits
  if (_ScoreInt + _ScoreGoldenInt + _ScoreLineInt > _ScoreTotalInt) then begin
    // prefer decreasing golden notes first, then regular notes, as a last resort just -1 the line bonus
    if (_ScoreGoldenInt > 0) then
      _ScoreGoldenInt := _ScoreGoldenInt - 1
    else if (_ScoreInt > 0) then
      _ScoreInt := _ScoreInt - 1
    else
      _ScoreLineInt := _ScoreLineInt - 1;
  end else if (_ScoreInt + _ScoreGoldenInt + _ScoreLineInt < _ScoreTotalInt) then begin
    // if the very first note(s) is golden AND this is the very beginning of the song, this might (temporarily) increase the wrong one.
    // it is estimated that there are way more songs that simply don't have golden notes at all and where it thus would pick the correct one.
    if (_ScoreInt > 0) or (_ScoreGoldenInt = 0) then
      _ScoreInt := _ScoreInt + 1
    else
      _ScoreGoldenInt := _ScoreGoldenInt + 1;
  end;
end;
procedure TPlayer.ResetScores();
begin
  DetectionReady := false;
  _Score := 0;
  _ScoreLine := 0;
  _ScoreGolden := 0;
  _ScoreInt := 0;
  _ScoreLineInt := 0;
  _ScoreGoldenInt := 0;
  _ScoreTotalInt := 0;
  ScorePerfectRemaining := MAX_SONG_SCORE;
  SetLength(SentenceScore, 0);
end;

procedure EnsurePlayerSentenceScores(PlayerIndex: integer);
var
  TrackIndex: integer;
begin
  if (PlayerIndex < 0) or (PlayerIndex > High(Player)) then
    Exit;

  if (Length(Player[PlayerIndex].SentenceScore) <> Length(CurrentSong.Tracks)) then
    SetLength(Player[PlayerIndex].SentenceScore, Length(CurrentSong.Tracks));

  for TrackIndex := 0 to High(CurrentSong.Tracks) do
  begin
    if (Length(Player[PlayerIndex].SentenceScore[TrackIndex]) <> Length(CurrentSong.Tracks[TrackIndex].Lines)) then
      SetLength(Player[PlayerIndex].SentenceScore[TrackIndex], Length(CurrentSong.Tracks[TrackIndex].Lines));
  end;
end;

procedure AddPlayerSentenceScore(PlayerIndex, Track, SentenceIndex: integer; Points: real);
begin
  if (PlayerIndex < 0) or (PlayerIndex > High(Player)) or
     (Track < 0) or (Track > High(CurrentSong.Tracks)) or
     (SentenceIndex < 0) or (SentenceIndex > CurrentSong.Tracks[Track].High) then
    Exit;

  EnsurePlayerSentenceScores(PlayerIndex);
  Player[PlayerIndex].SentenceScore[Track][SentenceIndex] :=
    Player[PlayerIndex].SentenceScore[Track][SentenceIndex] + Points;
end;

function GetPlayerSentenceScore(PlayerIndex, Track, SentenceIndex: integer; out Points: real): boolean;
begin
  Result := false;
  Points := 0;

  if (PlayerIndex < 0) or (PlayerIndex > High(Player)) or
     (Track < 0) or (Track > High(CurrentSong.Tracks)) or
     (SentenceIndex < 0) or (SentenceIndex > CurrentSong.Tracks[Track].High) then
    Exit;

  EnsurePlayerSentenceScores(PlayerIndex);
  Points := Player[PlayerIndex].SentenceScore[Track][SentenceIndex];
  Result := true;
end;

function GetTimeForBeats(BPM, Beats: real): real;
begin
  Result := 60 / BPM * Beats;
end;

function GetBeats(BPM, msTime: real): real;
begin
  Result := BPM * msTime / 60;
end;

function ShouldRunNoteDetection: boolean;
var
  PlayerIndex: integer;
  DelayBeats: real;
begin
  Result := LyricsState.CurrentBeatD >= 0;
  if Result then
    Exit;

  // A negative correction moves a player's scoring clock ahead of playback.
  // Start detection during the song pre-roll so every leading beat receives
  // the microphone sample captured at its shifted time.
  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    DelayBeats := GetBeats(CurrentSong.BPM, Ini.PlayerDelay[PlayerIndex] / 1000);
    if Floor(LyricsState.MidBeatD - DelayBeats) >= 0 then
    begin
      Result := true;
      Exit;
    end;
  end;
end;

function GetMidBeat(Time: real): real;
begin
  try
    if CurrentSong.BPM >= MIN_BPM then
      Result := Time * CurrentSong.BPM / 60
    else
      Result := 0;
  except
    on E : Exception do
      Result := 0;
  end;
end;

function GetTimeFromBeat(Beat: integer; SelfSong: TSong = nil): real;
var
  Song: TSong;
begin
  if (SelfSong <> nil) then
    Song := SelfSong
  else
    Song := CurrentSong;

  if Song.BPM >= MIN_BPM then
    Result := Song.GAP / 1000 + Beat * 60 / Song.BPM
  else
    Result := 0;
end;

procedure Sing(Screen: TScreenSingController);
var
  LineIndex:  integer;
  CountGr:    integer;
  TrackIndex: integer;
  PetGr:      integer;
begin
  LyricsState.UpdateBeats();

  PetGr := High(CurrentSong.Tracks);

  // sentences routines
  for CountGr := 0 to PetGr do //High(Tracks)
  begin;
    TrackIndex := CountGr;

    // old parts
    LyricsState.OldLine := CurrentSong.Tracks[TrackIndex].CurrentLine;

    // choose current parts
    for LineIndex := 0 to CurrentSong.Tracks[TrackIndex].High do
    begin
      if LyricsState.CurrentBeat >= CurrentSong.Tracks[TrackIndex].Lines[LineIndex].StartBeat then
        CurrentSong.Tracks[TrackIndex].CurrentLine := LineIndex;
    end;

    // clean player note if there is a new line
    // (optimization on halfbeat time)
    if CurrentSong.Tracks[TrackIndex].CurrentLine <> LyricsState.OldLine then
      NewSentence(TrackIndex, Screen);
  end; // for CountGr

  // make some operations on clicks
  if PlayersPlay > 0 then
    NewBeatClick(Screen);

  // make some operations when detecting new voice pitch
  if (PlayersPlay > 0) and ShouldRunNoteDetection then
    NewBeatDetect(Screen);
end;

procedure NewSentence(CP: integer; Screen: TScreenSingController);
var
  I: integer;
begin
  // clean note of player
  for I := 0 to High(Player) do
  begin
    if (not CurrentSong.isDuet) or (Player[I].Track = CP) then
    begin
      Player[I].LengthNote := 0;
      Player[I].HighNote := -1;
      SetLength(Player[I].Note, 0);
    end;
  end;

  Screen.onSentenceChange(CP, CurrentSong.Tracks[CP].CurrentLine)
end;

procedure NewBeatClick;
var
  LineIndex, NoteIndex, Track, PlayerIndex, ClickTrack, MinTone, MaxTone, PitchOffset: integer;
  Origin, EndTime, ClickTime, NoteEnd: real;
  ActiveTracks: array of boolean;
  ClickBeats: TStringList;
begin
  if BeatClickScheduled or (Ini.ClickAssist = 0) or (PlayersPlay <= 0) or (Length(Player) = 0) then Exit;
  if not Assigned(BeatClickOutput) then
  begin
    BeatClickOutput := TMidiOutput.Create(nil);
    if not BeatClickOutput.Open then
    begin
      FreeAndNil(BeatClickOutput);
      Exit;
    end;
    BeatClickClock := TSingClickClock.Create;
  end;
  Track := Player[0].Track;
  if (Track < 0) or (Track > High(CurrentSong.Tracks)) or
     (CurrentSong.BPM < MIN_BPM) then Exit;
  // Queue against the music timeline, including its silent roll-in. Playback
  // consumes the events sample by sample, independently of the video frames.
  Origin := AudioPlayback.Position;
  EndTime := LyricsState.TotalTime;
  BeatClickOutput.Stop;
  BeatClickOutput.SetPosition(0);
  BeatClickClock.Origin := Origin;
  BeatClickOutput.SetSyncSource(BeatClickClock);
  BeatClickOutput.SetVolume(EnsureRange(Ini.SfxVolume, 0, 100) / 100);
  MinTone := High(Integer);
  MaxTone := Low(Integer);
  for LineIndex := 0 to CurrentSong.Tracks[Track].High do
    for NoteIndex := 0 to CurrentSong.Tracks[Track].Lines[LineIndex].HighNote do
      with CurrentSong.Tracks[Track].Lines[LineIndex].Notes[NoteIndex] do
      if NoteType in [ntNormal, ntGolden] then
      begin
        MinTone := Min(MinTone, Tone);
        MaxTone := Max(MaxTone, Tone);
      end;
  // Match the editor's relative-tone and already-absolute-MIDI handling.
  PitchOffset := 60;
  if (MinTone >= 0) and (MaxTone <= 127) and
     ((MaxTone + 60 > 127) or ((MinTone >= 36) and (MaxTone <= 96) and
      (MaxTone + 60 > 96))) then PitchOffset := 0;
  for LineIndex := 0 to CurrentSong.Tracks[Track].High do
    for NoteIndex := 0 to CurrentSong.Tracks[Track].Lines[LineIndex].HighNote do
      with CurrentSong.Tracks[Track].Lines[LineIndex].Notes[NoteIndex] do
      begin
        ClickTime := GetTimeFromBeat(StartBeat);
        NoteEnd := Min(EndTime, GetTimeFromBeat(StartBeat + Duration));
        if (Ini.ClickAssist in [2, 3]) and (NoteEnd > Origin) and
           (ClickTime < EndTime) and (NoteType in [ntNormal, ntGolden]) then
        begin
          BeatClickOutput.QueueNoteOn(EnsureRange(Tone + PitchOffset, 0, 127),
            127, Max(0, ClickTime - Origin));
          BeatClickOutput.QueueNoteOff(EnsureRange(Tone + PitchOffset, 0, 127),
            NoteEnd - Origin);
        end;
      end;
  if Ini.ClickAssist in [1, 3] then
  begin
    SetLength(ActiveTracks, Length(CurrentSong.Tracks));
    for PlayerIndex := 0 to Min(PlayersPlay, Length(Player)) - 1 do
      if (Player[PlayerIndex].Track >= 0) and
        (Player[PlayerIndex].Track < Length(ActiveTracks)) then
        ActiveTracks[Player[PlayerIndex].Track] := true;
    ClickBeats := TStringList.Create;
    try
      ClickBeats.Sorted := true;
      for ClickTrack := 0 to High(ActiveTracks) do
        if ActiveTracks[ClickTrack] then
          for LineIndex := 0 to CurrentSong.Tracks[ClickTrack].High do
            for NoteIndex := 0 to CurrentSong.Tracks[ClickTrack].Lines[LineIndex].HighNote do
              with CurrentSong.Tracks[ClickTrack].Lines[LineIndex].Notes[NoteIndex] do
              begin
                ClickTime := GetTimeFromBeat(StartBeat);
                if (ClickTime >= Origin) and (ClickTime < EndTime) and
                  (ClickBeats.IndexOf(IntToStr(StartBeat)) < 0) then
                begin
                  ClickBeats.Add(IntToStr(StartBeat));
                  BeatClickOutput.QueueClick(127, ClickTime - Origin);
                end;
              end;
    finally
      ClickBeats.Free;
    end;
  end;
  BeatClickOutput.Play;
  BeatClickScheduled := true;
end;

procedure ConsumePerfectScorePotential(CP, OldBeat, CurrentBeat: integer; Screen: TScreenSingController; TargetPlayer: integer);
var
  FirstBeat: integer;
  LastBeat: integer;
  LineIndex: integer;
  NoteIndex: integer;
  PlayerIndex: integer;
  NoteFirstBeat: integer;
  NoteLastBeat: integer;
  OverlapFirstBeat: integer;
  OverlapLastBeat: integer;
  OverlapBeats: integer;
  SentenceEnd: integer;
  NonEmptySentenceCount: integer;
  MaxSongPoints: integer;
  NotePotential: real;
  LinePotential: real;
  PotentialPassed: real;
  LineBonus: real;
  Line: PLine;
  Note: PLineFragment;
begin
  if (CP < 0) or (CP > High(CurrentSong.Tracks)) then
    Exit;

  FirstBeat := OldBeat + 1;
  LastBeat := CurrentBeat;
  if LastBeat < FirstBeat then
    Exit;

  NotePotential := 0;
  if CurrentSong.Tracks[CP].ScoreValue > 0 then
  begin
    MaxSongPoints := MAX_SONG_SCORE - MAX_SONG_LINE_BONUS;

    for LineIndex := 0 to CurrentSong.Tracks[CP].High do
    begin
      Line := @CurrentSong.Tracks[CP].Lines[LineIndex];
      if (Line.HighNote < 0) then
        Continue;

      if (Line.Notes[Line.HighNote].StartBeat + Line.Notes[Line.HighNote].Duration - 1 < FirstBeat) then
        Continue;
      if (Line.Notes[0].StartBeat > LastBeat) then
        Break;

      for NoteIndex := 0 to Line.HighNote do
      begin
        Note := @Line.Notes[NoteIndex];
        if (Note.Duration <= 0) or Note.ScoreExcluded or (ScoreFactor[Note.NoteType] <= 0) then
          Continue;

        NoteFirstBeat := Note.StartBeat;
        NoteLastBeat := Note.StartBeat + Note.Duration - 1;
        if NoteLastBeat < FirstBeat then
          Continue;
        if NoteFirstBeat > LastBeat then
          Break;

        OverlapFirstBeat := Max(NoteFirstBeat, FirstBeat);
        OverlapLastBeat := Min(NoteLastBeat, LastBeat);
        OverlapBeats := OverlapLastBeat - OverlapFirstBeat + 1;

        if OverlapBeats > 0 then
          NotePotential := NotePotential +
            OverlapBeats *
            (MaxSongPoints / CurrentSong.Tracks[CP].ScoreValue) *
            ScoreFactor[Note.NoteType];
      end;
    end;
  end;

  LinePotential := 0;
  NonEmptySentenceCount := Length(CurrentSong.Tracks[CP].Lines) - Screen.NumEmptySentences[CP];
  if NonEmptySentenceCount > 0 then
  begin
    LineBonus := MAX_SONG_LINE_BONUS / NonEmptySentenceCount;

    for LineIndex := 0 to CurrentSong.Tracks[CP].High do
    begin
      Line := @CurrentSong.Tracks[CP].Lines[LineIndex];
      if (Line.HighNote < 0) or (Line.ScoreValue <= 0) then
        Continue;

      SentenceEnd := Line.Notes[Line.HighNote].StartBeat +
        Line.Notes[Line.HighNote].Duration;

      if SentenceEnd <= OldBeat then
        Continue;
      if Line.Notes[0].StartBeat > CurrentBeat then
        Break;

      if (OldBeat < SentenceEnd) and (CurrentBeat >= SentenceEnd) then
        LinePotential := LinePotential + LineBonus;
    end;
  end;

  PotentialPassed := NotePotential + LinePotential;
  if PotentialPassed <= 0 then
    Exit;

  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    if (PlayerIndex = TargetPlayer) and
      ((not CurrentSong.isDuet) or (Player[PlayerIndex].Track = CP)) then
    begin
      Player[PlayerIndex].ScorePerfectRemaining :=
        Player[PlayerIndex].ScorePerfectRemaining - PotentialPassed;
      if Player[PlayerIndex].ScorePerfectRemaining < 0 then
        Player[PlayerIndex].ScorePerfectRemaining := 0;
    end;
  end;
end;

function TrackHasRemotePlayer(Track: integer): boolean;
var
  PlayerIndex: integer;
begin
  Result := false;
  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    if ((not CurrentSong.isDuet) or (PlayerIndex mod 2 = Track)) and
       RemoteInputProcessor.HasAssignedPlayer(PlayerIndex) then
    begin
      Result := true;
      Exit;
    end;
  end;
end;

procedure UpdateRemainingScoreBar(CP: integer; Screen: TScreenSingController);
var
  PlayerIndex: integer;
begin
  if (Screen = nil) or (Screen.Scores = nil) then
    Exit;

  for PlayerIndex := 0 to High(Player) do
  begin
    if (not CurrentSong.isDuet) or (Player[PlayerIndex].Track = CP) then
    begin
      Screen.Scores.SetRemainingScore(
        byte(PlayerIndex),
        Player[PlayerIndex].ScorePerfectRemaining / MAX_SONG_SCORE,
        Player[PlayerIndex].Score + Player[PlayerIndex].ScoreGolden + Player[PlayerIndex].ScoreLine
      );
    end;
  end;
end;

function MaxConfiguredPlayerDelayMs(): integer;
var
  PlayerIndex: integer;
begin
  Result := 0;
  for PlayerIndex := 0 to PlayersPlay - 1 do
    Result := Max(Result, Ini.PlayerDelay[PlayerIndex]);
end;

procedure NewBeatDetect(Screen: TScreenSingController);
var CP, MaxCP: integer;
begin
  if not Assigned(Screen) then Exit;
  MaxCP := High(CurrentSong.Tracks);
  for CP := 0 to MaxCP do
  begin
    NewNote(CP, Screen);
    UpdateRemainingScoreBar(CP, Screen);
  end;
end;

procedure RecomputePlayerNotePerfects(CurrentPlayer: PPLayer; Line: PLine);
var
  PlayerNoteIndex: integer;
  LineFragmentIndex: integer;
begin
  for PlayerNoteIndex := 0 to CurrentPlayer.HighNote do
  begin
    CurrentPlayer.Note[PlayerNoteIndex].Perfect := false;
    for LineFragmentIndex := 0 to Line.HighNote do
    begin
      if (Line.Notes[LineFragmentIndex].StartBeat = CurrentPlayer.Note[PlayerNoteIndex].Start) and
         (Line.Notes[LineFragmentIndex].Duration = CurrentPlayer.Note[PlayerNoteIndex].Duration) and
         (Line.Notes[LineFragmentIndex].Tone = CurrentPlayer.Note[PlayerNoteIndex].Tone) then
      begin
        CurrentPlayer.Note[PlayerNoteIndex].Perfect := true;
        Break;
      end;
    end;
  end;
end;

procedure DeletePlayerNoteAt(CurrentPlayer: PPLayer; NoteIndex: integer);
var
  I: integer;
begin
  for I := NoteIndex to CurrentPlayer.HighNote - 1 do
    CurrentPlayer.Note[I] := CurrentPlayer.Note[I + 1];
  Dec(CurrentPlayer.LengthNote);
  Dec(CurrentPlayer.HighNote);
  SetLength(CurrentPlayer.Note, CurrentPlayer.LengthNote);
end;

function InsertPlayerBeatNote(CurrentPlayer: PPLayer; Beat: integer; Tone: real;
  Hit: boolean; NoteType: TNoteType): integer;
var
  InsertAt: integer;
  I: integer;
begin
  InsertAt := 0;
  while (InsertAt <= CurrentPlayer.HighNote) and
        (CurrentPlayer.Note[InsertAt].Start < Beat) do
    Inc(InsertAt);

  Inc(CurrentPlayer.LengthNote);
  Inc(CurrentPlayer.HighNote);
  SetLength(CurrentPlayer.Note, CurrentPlayer.LengthNote);
  for I := CurrentPlayer.HighNote downto InsertAt + 1 do
    CurrentPlayer.Note[I] := CurrentPlayer.Note[I - 1];

  CurrentPlayer.Note[InsertAt].Start := Beat;
  CurrentPlayer.Note[InsertAt].Duration := 1;
  CurrentPlayer.Note[InsertAt].Tone := Tone;
  CurrentPlayer.Note[InsertAt].Perfect := false;
  CurrentPlayer.Note[InsertAt].Hit := Hit;
  CurrentPlayer.Note[InsertAt].NoteType := NoteType;
  Result := InsertAt;
end;

procedure MergeAdjacentPlayerNotes(CurrentPlayer: PPLayer);
var
  I: integer;
begin
  I := 0;
  while I < CurrentPlayer.HighNote do
  begin
    if (CurrentPlayer.Note[I].Start + CurrentPlayer.Note[I].Duration = CurrentPlayer.Note[I + 1].Start) and
       (CurrentPlayer.Note[I].Tone = CurrentPlayer.Note[I + 1].Tone) and
       (CurrentPlayer.Note[I].Hit = CurrentPlayer.Note[I + 1].Hit) and
       (CurrentPlayer.Note[I].NoteType = CurrentPlayer.Note[I + 1].NoteType) then
    begin
      Inc(CurrentPlayer.Note[I].Duration, CurrentPlayer.Note[I + 1].Duration);
      DeletePlayerNoteAt(CurrentPlayer, I + 1);
    end
    else
      Inc(I);
  end;
end;

procedure UpsertRemotePlayerBeatNote(CurrentPlayer: PPLayer; Line: PLine;
  Beat, Tone: integer; Hit: boolean; NoteType: TNoteType);
var
  I: integer;
  OldStart: integer;
  OldEnd: integer;
  OldNote: TPlayerNote;
  InsertedIndex: integer;
begin
  for I := 0 to CurrentPlayer.HighNote do
  begin
    OldStart := CurrentPlayer.Note[I].Start;
    OldEnd := OldStart + CurrentPlayer.Note[I].Duration;
    if (Beat < OldStart) or (Beat >= OldEnd) then
      Continue;

    OldNote := CurrentPlayer.Note[I];
    if OldNote.Duration = 1 then
      DeletePlayerNoteAt(CurrentPlayer, I)
    else if Beat = OldStart then
    begin
      Inc(CurrentPlayer.Note[I].Start);
      Dec(CurrentPlayer.Note[I].Duration);
    end
    else if Beat = OldEnd - 1 then
      Dec(CurrentPlayer.Note[I].Duration)
    else
    begin
      CurrentPlayer.Note[I].Duration := Beat - OldStart;
      OldNote.Start := Beat + 1;
      OldNote.Duration := OldEnd - Beat - 1;
      InsertedIndex := InsertPlayerBeatNote(CurrentPlayer, OldNote.Start, OldNote.Tone, OldNote.Hit, OldNote.NoteType);
      CurrentPlayer.Note[InsertedIndex].Duration := OldNote.Duration;
    end;
    Break;
  end;

  InsertedIndex := InsertPlayerBeatNote(CurrentPlayer, Beat, Tone, Hit, NoteType);
  MergeAdjacentPlayerNotes(CurrentPlayer);
  RecomputePlayerNotePerfects(CurrentPlayer, Line);
end;

procedure NewNote(CP: integer; Screen: TScreenSingController);
var
  LineFragmentIndex:   integer;
  CurrentLineFragment: PLineFragment;
  PlayerIndex:         integer;
  CurrentSound:        TCaptureBuffer;
  CurrentPlayer:       PPlayer;
  LastPlayerNote:      PPlayerNote;
  Line:                PLine;
  SentenceIndex:       integer;
  SentenceMin:         integer;
  SentenceMax:         integer;
  SentenceDetected:    integer; // sentence of detected note
  ActualBeat:          integer;
  ActualTone:          integer;
  NoteAvailable:       boolean;
  NewNote:             boolean;
  Range:               integer;
  NoteHit:             boolean;
  MaxSongPoints:       integer; // max. points for the song (without line bonus)
  CurNotePoints:       real;    // Points for the cur. Note (PointsperNote * ScoreFactor[CurNote])
  CurrentNoteType:     TNoteType;
  DelayBeats:          real;
  PlayerDelayMs:       integer;
  PlayerOldBeat:       integer;
  PlayerCurBeat:       integer;
  FirstBeatToAnalyze:  integer;
  IsRemotePlayer:      boolean;
  CanUpdatePlayerNote: boolean;
  SongTimeUs:          int64;
  RemoteTone:          TRemoteToneSample;
  EndLineIndex, SentenceEnd: integer;
begin
  ActualTone := 0;
  NoteHit := false;

  // TODO: add duet mode support
  // use CurrentSong.Tracks[LineSetIndex] with LineSetIndex depending on the current player

  // count min and max sentence range for checking
  // (detection is delayed to the notes we see on the screen)
  SentenceMin := 0;
  SentenceMax := CurrentSong.Tracks[CP].High;

  // analyze player signals
  for PlayerIndex := 0 to PlayersPlay-1 do
  begin
    if (not CurrentSong.isDuet) or (Player[PlayerIndex].Track = CP) then
    begin

      IsRemotePlayer := RemoteInputProcessor.HasAssignedPlayer(PlayerIndex) and
        not (PhoneAudio.Enabled and (PlayerIndex = 0));
      PlayerDelayMs := Ini.PlayerDelay[PlayerIndex];
      if IsRemotePlayer then
      begin
        // CurrentBeatD already includes Ini.MicDelay. Remote beat frames are
        // placed by song beat on the phone, so only delay scoring long enough
        // for late network frames to arrive, relative to the slowest input path.
        PlayerDelayMs := Max(RemoteInputProcessor.RequiredGameDelayMs,
          Ini.MicDelay + MaxConfiguredPlayerDelayMs + REMOTE_INPUT_GAME_DELAY_MARGIN_MS) - Ini.MicDelay;
      end;

      // delay in beats (Ini.PlayerDelay or compensated remote game delay are ms)
      DelayBeats := GetBeats(CurrentSong.BPM, PlayerDelayMs / 1000);
      if IsRemotePlayer then
      begin
        Player[PlayerIndex].DetectionReady := true;
        Player[PlayerIndex].DetectionDelay := PlayerDelayMs;
        PlayerCurBeat := Floor(LyricsState.CurrentBeatD - DelayBeats);
        if Screen.ScoringTailActive then
          PlayerCurBeat := Min(PlayerCurBeat, Screen.ScoringTailEndBeat);
        if PlayerCurBeat < 0 then PlayerCurBeat := 0;
        FirstBeatToAnalyze := Max(0, PlayerCurBeat - REMOTE_INPUT_LATE_BEAT_WINDOW);
      end
      else
      begin
        // delay in beats (Ini.PlayerDelay is ms)
        if not Player[PlayerIndex].DetectionReady then
        begin
          Player[PlayerIndex].DetectionDelay := Ini.PlayerDelay[PlayerIndex];
          Player[PlayerIndex].DetectionReady := true;
          DelayBeats := GetBeats(CurrentSong.BPM, Player[PlayerIndex].DetectionDelay / 1000);
          Player[PlayerIndex].DetectionBeat := Floor(LyricsState.MidBeatD - DelayBeats) - 1;
        end;
        DelayBeats := GetBeats(CurrentSong.BPM, Player[PlayerIndex].DetectionDelay / 1000);
        PlayerOldBeat := Player[PlayerIndex].DetectionBeat;
        PlayerCurBeat := Floor(LyricsState.MidBeatD - DelayBeats);
        if Screen.ScoringTailActive then
          PlayerCurBeat := Min(PlayerCurBeat, Screen.ScoringTailEndBeat);
        FirstBeatToAnalyze := PlayerOldBeat + 1;

      end;

      // Other players can still be before their shifted scoring start when a
      // negative-delay player begins during pre-roll. Move their cursor only;
      // do not analyze or consume score potential before beat zero.
      if PlayerCurBeat < 0 then
      begin
        Player[PlayerIndex].DetectionBeat := PlayerCurBeat;
        Continue;
      end;

      for ActualBeat := FirstBeatToAnalyze to PlayerCurBeat do

      begin
        // Finish each player's line after its last delayed beat and before
        // scoring any following line. Other players may still be singing it.
        for EndLineIndex := 0 to CurrentSong.Tracks[CP].High do
          with CurrentSong.Tracks[CP].Lines[EndLineIndex] do
            if HighNote >= 0 then
            begin
              SentenceEnd := Notes[HighNote].StartBeat + Notes[HighNote].Duration;
              if ActualBeat = SentenceEnd then
                Screen.OnSentenceEnd(CP, EndLineIndex, PlayerIndex);
            end;
        // check for an active note at the current time defined in the lyrics
        NoteAvailable := false;
        SentenceDetected := SentenceMin;
        for SentenceIndex := SentenceMin to SentenceMax do
        begin
          Line := @CurrentSong.Tracks[CP].Lines[SentenceIndex];
          for LineFragmentIndex := 0 to Line.HighNote do
          begin
            CurrentLineFragment := @Line.Notes[LineFragmentIndex];
            // check if line is active
            if ((CurrentLineFragment.StartBeat <= ActualBeat) and
              (CurrentLineFragment.StartBeat + CurrentLineFragment.Duration-1 >= ActualBeat)) and
              not CurrentLineFragment.ScoreExcluded and
              (ScoreFactor[CurrentLineFragment.NoteType] > 0) and
              ((ScreenSong.Mode <> smMedley) or
               ((CurrentLineFragment.StartBeat >= CurrentSong.Medley.StartBeat) and
                (CurrentLineFragment.StartBeat < CurrentSong.Medley.EndBeat))) and
              (CurrentLineFragment.Duration > 0) then
            begin
              SentenceDetected := SentenceIndex;
              NoteAvailable := true;
              Break;
            end;
          end;
          // TODO: break here, if NoteAvailable is true? We would then use the first instead
          // of the last note matching the current beat if notes overlap. But notes
          // should not overlap at all.
          //if (NoteAvailable) then
          //  Break;
        end;

        CurrentPlayer := @Player[PlayerIndex];
        CurrentSound := AudioInputProcessor.Sound[PlayerIndex];

        // at the beginning of the song there is no previous note
        if (Length(CurrentPlayer.Note) > 0) and (CurrentPlayer.HighNote > -1) then
          LastPlayerNote := @CurrentPlayer.Note[CurrentPlayer.HighNote]
        else
          LastPlayerNote := nil;
        CanUpdatePlayerNote := (LastPlayerNote = nil) or
          (ActualBeat >= LastPlayerNote.Start + LastPlayerNote.Duration);

        Line := nil;
        CurrentLineFragment := nil;
        CurrentNoteType := ntNormal;

        if NoteAvailable then
        begin
          Line := @CurrentSong.Tracks[CP].Lines[SentenceDetected];
          for LineFragmentIndex := 0 to Line.HighNote do
          begin
            if (Line.Notes[LineFragmentIndex].StartBeat <= ActualBeat) and
               (Line.Notes[LineFragmentIndex].StartBeat + Line.Notes[LineFragmentIndex].Duration > ActualBeat) then
            begin
              CurrentLineFragment := @Line.Notes[LineFragmentIndex];
              CurrentNoteType := CurrentLineFragment.NoteType;
              Break;
            end;
          end;
        end;

        CurNotePoints := 0;
        if (CurrentLineFragment <> nil) and (CurrentSong.Tracks[CP].ScoreValue > 0) then
        begin
          MaxSongPoints := MAX_SONG_SCORE - MAX_SONG_LINE_BONUS;

          // Note: ScoreValue is the sum of all note values of the song
          // (MaxSongPoints / ScoreValue) is the points that a player
          // gets for a hit of one beat of a normal note
          // CurNotePoints is the amount of points that is meassured
          // for a hit of the note per full beat
          CurNotePoints := (MaxSongPoints / CurrentSong.Tracks[CP].ScoreValue) *
            ScoreFactor[CurrentLineFragment.NoteType];
        end;

        Line := nil;
        CurrentLineFragment := nil;
        CurrentNoteType := ntNormal;

        if NoteAvailable then
        begin
          Line := @CurrentSong.Tracks[CP].Lines[SentenceDetected];
          for LineFragmentIndex := 0 to Line.HighNote do
          begin
            if (Line.Notes[LineFragmentIndex].StartBeat <= ActualBeat) and
               (Line.Notes[LineFragmentIndex].StartBeat + Line.Notes[LineFragmentIndex].Duration > ActualBeat) then
            begin
              CurrentLineFragment := @Line.Notes[LineFragmentIndex];
              CurrentNoteType := CurrentLineFragment.NoteType;
              Break;
            end;
          end;
        end;

        CurNotePoints := 0;
        if (CurrentLineFragment <> nil) and (CurrentSong.Tracks[CP].ScoreValue > 0) then
        begin
          MaxSongPoints := MAX_SONG_SCORE - MAX_SONG_LINE_BONUS;

          // Note: ScoreValue is the sum of all note values of the song
          // (MaxSongPoints / ScoreValue) is the points that a player
          // gets for a hit of one beat of a normal note
          // CurNotePoints is the amount of points that is meassured
          // for a hit of the note per full beat
          CurNotePoints := (MaxSongPoints / CurrentSong.Tracks[CP].ScoreValue) *
            ScoreFactor[CurrentLineFragment.NoteType];
        end;

        // analyze buffer
        if IsRemotePlayer then
        begin
          if not NoteAvailable then
            Continue;

          SongTimeUs := Round(GetTimeFromBeat(ActualBeat) * 1000000);
          if not RemoteInputProcessor.TryConsumeToneForBeat(PlayerIndex, ActualBeat, SongTimeUs, RemoteTone) then
            Continue;

          CurrentSound.ToneValid := RemoteTone.ToneValid;
          CurrentSound.Tone := RemoteTone.Tone;
          CurrentSound.ToneAbs := RemoteTone.ToneAbs;
        end
        else
        begin
          CurrentSound.AnalyzeBuffer;
        end;

        // add some noise
        // TODO: do we need this?
        //LyricsState.Tone := LyricsState.Tone + Round(Random(3)) - 1;

        // add note if possible
        if (CurrentSound.ToneValid and (CurrentLineFragment <> nil)) then
        begin
          // move players tone to proper octave
          while (CurrentSound.Tone - CurrentLineFragment.Tone > 6) do
            CurrentSound.Tone := CurrentSound.Tone - 12;

          while (CurrentSound.Tone - CurrentLineFragment.Tone < -6) do
            CurrentSound.Tone := CurrentSound.Tone + 12;

          // half size notes patch
          NoteHit := false;
          ActualTone := CurrentSound.Tone;
          if (ScreenSong.Mode = smNormal) or (ScreenSong.Mode = smMedley) then
            Range := 2 - Player[PlayerIndex].Level
          else
            Range := 2 - Ini.Difficulty;

          // check if the player hit the correct tone within the tolerated range
          if (ScoreFactor[CurrentLineFragment.NoteType] > 0) and
            ((Abs(CurrentLineFragment.Tone - CurrentSound.Tone) <= Range) or IsUnpitchedNote(CurrentLineFragment.NoteType)) then
          begin
            // adjust the players tone to the correct one
            // TODO: do we need to do this?
            // Philipp: I think we do, at least when we draw the notes.
            //          Otherwise the notehit thing would be shifted to the
            //          correct unhit note. I think this will look kind of strange.
            ActualTone := CurrentLineFragment.DisplayTone;

            // half size notes patch
            NoteHit := true;

            case CurrentLineFragment.NoteType of
              ntFreestyle, ntNormal:    CurrentPlayer.Score       := CurrentPlayer.Score       + CurNotePoints;
              ntGolden:    CurrentPlayer.ScoreGolden := CurrentPlayer.ScoreGolden + CurNotePoints;
              ntRap:       CurrentPlayer.Score       := CurrentPlayer.Score       + CurNotePoints;
              ntRapGolden: CurrentPlayer.ScoreGolden := CurrentPlayer.ScoreGolden + CurNotePoints;
            end;
            AddPlayerSentenceScore(PlayerIndex, CP, SentenceDetected, CurNotePoints);
          end; // operation

          // check if we have to add a new note or extend the note's length
          if (SentenceDetected = CurrentSong.Tracks[CP].CurrentLine) then
          begin
            if IsRemotePlayer then
              UpsertRemotePlayerBeatNote(CurrentPlayer, Line, ActualBeat,
                ActualTone, NoteHit, CurrentNoteType)
            else if CanUpdatePlayerNote then
            begin
              // we will add a new note
              NewNote := true;

              // if previous note (if any) was the same, extend previous note
              if ((CurrentPlayer.LengthNote > 0) and
                  (LastPlayerNote <> nil) and
                  (LastPlayerNote.Tone = ActualTone) and
                  ((LastPlayerNote.Start + LastPlayerNote.Duration) = ActualBeat)) then
              begin
                NewNote := false;
              end;

              // if is not as new note to control
              for LineFragmentIndex := 0 to Line.HighNote do

              begin
                if (Line.Notes[LineFragmentIndex].StartBeat = ActualBeat) then
                  NewNote := true;
              end;

              // add new note
              if NewNote then
              begin
                // new note
                Inc(CurrentPlayer.LengthNote);
                Inc(CurrentPlayer.HighNote);
                SetLength(CurrentPlayer.Note, CurrentPlayer.LengthNote);

                // update player's last note
                LastPlayerNote := @CurrentPlayer.Note[CurrentPlayer.HighNote];
                with LastPlayerNote^ do
                begin
                  Start    := ActualBeat;
                  Duration := 1;
                  Tone     := ActualTone; // Tone || ToneAbs
                  //Detect := LyricsState.MidBeat; // Not used!
                  Hit      := NoteHit; // half note patch
                  NoteType := CurrentNoteType;
                end;
              end
              else
              begin
                // extend note length
                if (LastPlayerNote <> nil) then
                  Inc(LastPlayerNote.Duration);
              end;

              // check if the new/extended note is perfect and then light the star (on Draw)
              for LineFragmentIndex := 0 to Line.HighNote do
              begin
                CurrentLineFragment := @Line.Notes[LineFragmentIndex];
                if (CurrentLineFragment.StartBeat  = LastPlayerNote.Start) and
                  (CurrentLineFragment.Duration = LastPlayerNote.Duration) and
                  (CurrentLineFragment.DisplayTone = LastPlayerNote.Tone) then
                begin
                  LastPlayerNote.Perfect := true;
                end;
              end;
            end;
          end; // if SentenceDetected = SentenceMax

        end; // if Detected
      end; // for ActualBeat
      if IsRemotePlayer then
        Player[PlayerIndex].DetectionBeat := PlayerCurBeat
      else
      begin
        ConsumePerfectScorePotential(CP, PlayerOldBeat, PlayerCurBeat, Screen, PlayerIndex);
        Player[PlayerIndex].DetectionBeat := Max(PlayerOldBeat, PlayerCurBeat);
      end;
    end;
  end; // for PlayerIndex
  //Log.LogStatus('EndBeat', 'NewBeat');
end;

finalization
  FreeAndNil(BeatClickOutput);
  FreeAndNil(BeatClickClock);

end.
