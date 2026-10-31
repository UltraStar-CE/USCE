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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenSing.pas $
 * $Id: UScreenSing.pas 3150 2015-10-20 00:07:57Z basisbit $
 *}

unit UScreenSingView;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDocumentUI,
  UPath,
  SysUtils,
  sdl2,
  UText,
  UCommon,
  UGraphicClasses,
  UHookableEvent,
  UIni,
  ULog,
  ULyrics,
  UAvatars,
  UGapCountdown,
  UMenu,
  UMusic,
  UPlayerLayout,
  URenderer,
  USingScores,
  USongs,
  UThemes,
  UScale,
  UTime,
  USkins;

type
  TSingDocumentNotice = record
    PlayerIndex, Rating, TotalScore, Gain: integer;
    Started: cardinal;
  end;
  TScreenSingView = class
  private
    DocumentUI: TDocumentUI;
    DocumentPlayerCount: integer;
    DocumentVoiceKey: UTF8String;
    MessageValue, SongTitleValue, DisplayClock: UTF8String;
    MessageVisible, SongTitleVisible: boolean;
    MessageAlpha, SongTitleAlpha, CountdownPhase: real;
    CountdownValue: integer;
    DocumentNotices: array of TSingDocumentNotice;
    PreviousNoticeScore: array[0..IMaxPlayerCount-1] of integer;
    BestScore, AverageScore: array[0..2] of integer;
    HighscoresReady: boolean;
    GapCountdown: TGapCountdown;
    LanePanelTexture: TTexture;
    HeaderTexture: TTexture;
    DefaultAvatarTexture: TTexture;
    procedure SetDocumentNumber(const Name: UTF8String; Value: real);
    procedure PrepareDocumentSegments;
    procedure EnsureDocumentPlayers;
    procedure EnsureDocumentVoices;
    procedure SyncDocumentHUD;
    procedure DrawDocumentCanvases;
    procedure PositionDocumentVideo;
    function GetDocumentActive: boolean;
    function GetSongTitle: UTF8String;
    procedure SetSongTitle(const Value: UTF8String);
    procedure DrawHeaders;
    procedure DrawLanePanels;
    procedure DrawGapCountdown;
  public

    //StaticDuet: array of cardinal;
    // lyrics bar fields
    StaticLyricsBar: integer;
    StaticLyricsBarDuet: integer;

    // timebar fields
    StaticTimeBar: integer;
    StaticTimeProgress: integer;
    TextTimeLabelText: integer;
    TextTimeText: integer;

    PlayerFrameSlots:  array [1..UIni.IMaxPlayerCount, 0..UIni.IMaxPlayerCount-1] of integer;
    PlayerAvatarSlots: array [1..UIni.IMaxPlayerCount, 0..UIni.IMaxPlayerCount-1] of integer;
    PlayerTextSlots:   array [1..UIni.IMaxPlayerCount, 0..UIni.IMaxPlayerCount-1] of integer;


    StaticPausePopup: integer;

    SongNameStatic:   integer;
    SongNameText:     integer;



    property DocumentActive: boolean read GetDocumentActive;
    property SongTitle: UTF8String read GetSongTitle write SetSongTitle;
    procedure ResetHUD;
    procedure ResetScoreFeedback;
    function PlayerHeaderCenter(PlayerIndex: integer): real;
    procedure PositionDocumentVoice(DisplayIndex: integer);
    function DocumentMouse(Button: integer; Down: boolean; X, Y: integer; out SeekPosition: real): boolean;
    procedure NotifyRating(PlayerIndex, Rating, TotalScore: integer);
    constructor Create;
    destructor Destroy; override;

    procedure PrepareGapCountdown;
    procedure DrawMedleyCountdown();
    procedure DrawCountIn();
    procedure DrawCountdown(timeDiff: real);
    function Draw: boolean;

    procedure SwapToScreen(Screen: integer);

    procedure WriteMessage(msg: UTF8String);
    procedure FadeMessage();
    procedure CloseMessage();

    procedure MedleyTitleFadeOut();

    function GetLyricColor(Color: integer): TRGB;

    procedure DrawInfoLyricBar();
  end;
var
  lastVolume: single;

implementation

uses
  Classes,
  Math,
  UDatabase,
  UDllManager,
  UDraw,
  UGraphic,
  ULanguage,
  UNote,
  URecord,
  USong,
  UDisplay,
  UParty,
  UPathUtils,
  UUnicodeUtils,
  UScreenSingController,
  UWebcam,
  UWebSDK, UMenuBackground;

const
  uiSingingScreen = 'singing';
  uiSingingPause = 'singing.pause.toggle';
  uiSingingTimeMode = 'singing.time.mode';
  uiSingingSeek = 'singing.seek';
  MAX_MESSAGE = 3;

type
  TSlotArray = array of integer;

procedure GetSingWidgetSlots(const View: TScreenSingView; LayoutPlayerCount: integer;
  out FrameSlots, AvatarSlots: TSlotArray);
var
  SlotIndex: integer;
begin
  SetLength(FrameSlots, LayoutPlayerCount);
  SetLength(AvatarSlots, LayoutPlayerCount);
  for SlotIndex := 0 to LayoutPlayerCount - 1 do
  begin
    FrameSlots[SlotIndex] := View.PlayerFrameSlots[LayoutPlayerCount, SlotIndex];
    AvatarSlots[SlotIndex] := View.PlayerAvatarSlots[LayoutPlayerCount, SlotIndex];
  end;
end;

procedure GetSingTextSlots(const View: TScreenSingView; LayoutPlayerCount: integer;
  out TextSlots: TSlotArray);
var
  SlotIndex: integer;
begin
  SetLength(TextSlots, LayoutPlayerCount);
  for SlotIndex := 0 to LayoutPlayerCount - 1 do
    TextSlots[SlotIndex] := View.PlayerTextSlots[LayoutPlayerCount, SlotIndex];
end;

function GetSingPlayerColor(PlayerIndex: integer): TRGB;
begin
  Result := GetPlayerColor(Ini.PlayerColor[PlayerIndex]);
end;

function IsCurrentSongDuet: boolean;
begin
  Result := Assigned(CurrentSong) and CurrentSong.isDuet;
end;

procedure TScreenSingView.SetDocumentNumber(const Name: UTF8String; Value: real);
var F: TFormatSettings;
begin
  F := DefaultFormatSettings; F.DecimalSeparator := '.';
  DocumentUI.SetModel(Name, FloatToStr(Value, F), 3);
end;

procedure TScreenSingView.PrepareDocumentSegments;
var Track, Line, Count: integer; Prefix: UTF8String; Col: TRGB;
begin
  if not DocumentActive then Exit;
  Count := 0;
  for Track := 0 to High(CurrentSong.Tracks) do
    for Line := 0 to High(CurrentSong.Tracks[Track].Lines) do
      with CurrentSong.Tracks[Track].Lines[Line] do
        if (Length(Notes) > 0) and ((ScreenSong.Mode <> smMedley) or
          (Notes[0].StartBeat >= CurrentSong.Medley.StartBeat)) then Inc(Count);
  DocumentUI.SetArray('singing.segments', Count);
  Count := 0;
  for Track := 0 to High(CurrentSong.Tracks) do
    for Line := 0 to High(CurrentSong.Tracks[Track].Lines) do
      with CurrentSong.Tracks[Track].Lines[Line] do
        if (Length(Notes) > 0) and ((ScreenSong.Mode <> smMedley) or
          (Notes[0].StartBeat >= CurrentSong.Medley.StartBeat)) then
        begin
          Prefix := 'singing.segments[' + IntToStr(Count) + '].';
          DocumentUI.SetModel(Prefix + 'id', IntToStr(Count), 1);
          SetDocumentNumber(Prefix + 'start', GetTimeFromBeat(Notes[0].StartBeat));
          SetDocumentNumber(Prefix + 'end', GetTimeFromBeat(Notes[HighNote].EndBeat));
          Col := GetLyricColor(Ini.SingColor[Track mod IMaxPlayerCount]);
          DocumentUI.SetModel(Prefix + 'color', Format('#%.2x%.2x%.2x', [Round(Col.R*255), Round(Col.G*255), Round(Col.B*255)]));
          Inc(Count);
        end;
end;

function TScreenSingView.GetDocumentActive: boolean;
begin Result := DocumentUI <> nil; end;

function TScreenSingView.GetSongTitle: UTF8String;
begin
  if DocumentActive then Result := SongTitleValue
  else Result := ScreenSing.Text[SongNameText].Text;
end;

procedure TScreenSingView.SetSongTitle(const Value: UTF8String);
begin
  SongTitleValue := Value;
  if not DocumentActive then ScreenSing.Text[SongNameText].Text := Value;
end;

procedure TScreenSingView.ResetHUD;
begin
  if not DocumentActive then Exit;
  MessageVisible := false; MessageValue := ''; MessageAlpha := 0;
  SongTitleVisible := false; SongTitleValue := ''; SongTitleAlpha := 0;
  CountdownValue := 0; CountdownPhase := 0;
  HighscoresReady := false;
  DocumentPlayerCount := -1; DocumentVoiceKey := '';
  ResetScoreFeedback;
  FillChar(BestScore, SizeOf(BestScore), 0);
  FillChar(AverageScore, SizeOf(AverageScore), 0);
end;

procedure TScreenSingView.ResetScoreFeedback;
begin
  if not DocumentActive then Exit;
  SetLength(DocumentNotices, 0);
  FillChar(PreviousNoticeScore, SizeOf(PreviousNoticeScore), 0);
end;

procedure TScreenSingView.EnsureDocumentPlayers;
var I: integer; Prefix: UTF8String;
begin
  if not DocumentActive then Exit;
  DocumentUI.SetModel('singing.count', IntToStr(PlayersPlay), 1);
  DocumentUI.SetModel('singing.duet', IntToStr(Ord(IsCurrentSongDuet)), 2);
  if DocumentPlayerCount = PlayersPlay then Exit;
  DocumentPlayerCount := PlayersPlay;
  DocumentUI.SetArray('singing.players', PlayersPlay);
  if not IsCurrentSongDuet then
  begin
    DocumentUI.SetArray('singing.upperVoices', 0); DocumentUI.SetArray('singing.lowerVoices', 0);
    DocumentUI.SetModel('singing.upperVoicesCount', '0', 1); DocumentUI.SetModel('singing.lowerVoicesCount', '0', 1);
  end;
  for I := 0 to PlayersPlay - 1 do
  begin
    Prefix := 'singing.players[' + IntToStr(I) + '].';
    DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
  end;
end;

function TScreenSingView.PlayerHeaderCenter(PlayerIndex: integer): real;
var Bounds: TDocumentRegion;
begin
  EnsureDocumentPlayers;
  if DocumentUI.Region('singing-player-header-' + IntToStr(PlayerIndex), Bounds) then
    Result := Bounds.Y + Bounds.H / 2
  else Result := RenderH / 2;
end;

procedure TScreenSingView.EnsureDocumentVoices;
var I, Voice, Bank, Index: integer; Key, Prefix, GroupName: UTF8String; Col: TRGB;
begin
  Key := '';
  for I := 0 to High(ScreenSing.DisplayedVoices) do
    Key := Key + IntToStr(ScreenSing.DisplayedVoices[I]) + ':' + IntToStr(ScreenSing.DisplayedVoiceBanks[I]) + ';';
  if Key = DocumentVoiceKey then Exit;
  DocumentVoiceKey := Key;
  for Bank := 0 to 1 do
  begin
    if Bank = 0 then GroupName := 'upperVoices' else GroupName := 'lowerVoices';
    DocumentUI.SetModel('singing.' + GroupName + 'Count', IntToStr(ScreenSing.VoiceBankCounts[Bank]), 1);
    DocumentUI.SetArray('singing.' + GroupName, ScreenSing.VoiceBankCounts[Bank]);
    Index := 0;
    for I := 0 to High(ScreenSing.DisplayedVoices) do
      if ScreenSing.DisplayedVoiceBanks[I] = Bank then
      begin
        Voice := ScreenSing.DisplayedVoices[I];
        Prefix := 'singing.' + GroupName + '[' + IntToStr(Index) + '].';
        DocumentUI.SetModel(Prefix + 'id', IntToStr(Voice), 1);
        DocumentUI.SetModel(Prefix + 'number', IntToStr(Voice + 1), 1);
        DocumentUI.SetModel(Prefix + 'bank', IntToStr(Bank), 1);
        Col.R := ScreenSing.VoiceLyrics[Voice].LineColor_act.R;
        Col.G := ScreenSing.VoiceLyrics[Voice].LineColor_act.G;
        Col.B := ScreenSing.VoiceLyrics[Voice].LineColor_act.B;
        DocumentUI.SetModel(Prefix + 'color', Format('#%.2x%.2x%.2x', [Round(Col.R * 255), Round(Col.G * 255), Round(Col.B * 255)]));
        Inc(Index);
      end;
  end;
end;

procedure TScreenSingView.PositionDocumentVoice(DisplayIndex: integer);
var Bounds: TDocumentRegion; Voice, Bank: integer; Engine: TLyricEngine;
begin
  EnsureDocumentVoices;
  Voice := ScreenSing.DisplayedVoices[DisplayIndex];
  Bank := ScreenSing.DisplayedVoiceBanks[DisplayIndex];
  if not DocumentUI.Region('singing-voice-' + IntToStr(Voice) + '-' + IntToStr(Bank), Bounds) then Exit;
  Engine := ScreenSing.VoiceLyrics[Voice];
  Engine.Compact := ScreenSing.VoiceBankCounts[Bank] > 1;
  Engine.UpperLineX := Bounds.X; Engine.UpperLineY := Bounds.Y;
  Engine.UpperLineW := Bounds.W; Engine.UpperLineH := Bounds.H;
  Engine.LowerLineX := Bounds.X; Engine.LowerLineY := Bounds.Y;
  Engine.LowerLineW := Bounds.W; Engine.LowerLineH := Bounds.H;
  if not Engine.Compact then
  begin
    Engine.UpperLineH := Bounds.H / 2;
    Engine.LowerLineY := Bounds.Y + Bounds.H / 2;
    Engine.LowerLineH := Bounds.H / 2;
  end;
  Engine.UpdateLineMetrics;
end;

procedure TScreenSingView.PositionDocumentVideo;
var Bounds: TDocumentRegion;
begin
  if not DocumentUI.Region('singing-video', Bounds) then Exit;
  ScreenSing.fCurrentVideo.SetScreenPosition(Bounds.X, Bounds.Y, 0);
  ScreenSing.fCurrentVideo.Width := Bounds.W;
  ScreenSing.fCurrentVideo.Height := Bounds.H;
end;

procedure TScreenSingView.NotifyRating(PlayerIndex, Rating, TotalScore: integer);
var N: integer;
begin
  if not DocumentActive then Exit;
  N := Length(DocumentNotices);
  SetLength(DocumentNotices, N + 1);
  DocumentNotices[N].PlayerIndex := PlayerIndex;
  DocumentNotices[N].Rating := Rating;
  DocumentNotices[N].TotalScore := TotalScore;
  DocumentNotices[N].Gain := TotalScore - PreviousNoticeScore[PlayerIndex];
  DocumentNotices[N].Started := SDL_GetTicks;
  PreviousNoticeScore[PlayerIndex] := TotalScore;
end;

function TScreenSingView.DocumentMouse(Button: integer; Down: boolean; X, Y: integer;
  out SeekPosition: real): boolean;
var Bounds: TDocumentRegion; GX, GY, StartTime, EndTime: real; Action: UTF8String;
begin
  Result := false;
  SeekPosition := 0;
  if Button = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, Down)
  else DocumentUI.Mouse(X, Y);
  Action := DocumentUI.TakeAction;
  if Action = uiSingingSeek then Exit;
  if (Button = SDL_BUTTON_LEFT) and Down and ScreenSing.ShowFinish and
    not ScreenSing.FadeOut and ScreenSing.Settings.TimeBarVisible and
    DocumentUI.Region('singing-progress', Bounds) and (Bounds.W > 0) then
  begin
    GX := X * RenderW / ScreenW; GY := Y * RenderH / ScreenH;
    if (GX >= Bounds.X) and (GX <= Bounds.X + Bounds.W) and
      (GY >= Bounds.Y - 4) and (GY <= Bounds.Y + Bounds.H + 4) then
    begin
      StartTime := CurrentSong.Start; EndTime := LyricsState.TotalTime;
      if ScreenSong.Mode = smMedley then StartTime := ScreenSing.MedleyStart;
      if EndTime > StartTime then
      begin SeekPosition := StartTime + (EndTime - StartTime) * (GX - Bounds.X) / Bounds.W; Exit(true); end;
    end;
  end;
  if Action = uiSingingPause then ScreenSing.Pause
  else if Action = uiSingingTimeMode then ScreenSing.CycleTimebarMode;
end;

procedure TScreenSingView.SyncDocumentHUD;
const RatingKeys: array[0..8] of UTF8String = ('POPUP_AWFUL', 'POPUP_AWFUL', 'POPUP_POOR',
  'POPUP_BAD', 'POPUP_NOTBAD', 'POPUP_GOOD', 'POPUP_GREAT', 'POPUP_AWESOME', 'POPUP_PERFECT');
var I, J, Level: integer; Prefix, Name, ImagePath: UTF8String;
    Color: TRGB; ScorePlayer: TScorePlayer; CurrentTime, StartTime, EndTime: real;
    Age, Lifetime, Potential, ClockPosition, ClockDuration, ClockValue: real; ClockPrefix: UTF8String; UpperText, LowerText: boolean;
  procedure Bool(const Name: UTF8String; Value: boolean);
  begin DocumentUI.SetModel('singing.' + Name, IntToStr(Ord(Value)), 2); end;
  function ColorText(const C: TRGB): UTF8String;
  begin Result := Format('#%.2x%.2x%.2x', [Round(C.R * 255), Round(C.G * 255), Round(C.B * 255)]); end;
begin
  EnsureDocumentPlayers;
  if CurrentSong = nil then Exit;
  if not HighscoresReady and Assigned(DataBase) and ScreenSing.Settings.ScoresVisible and
    ((Ini.SingScores = Ord(sibBoth)) or (Ini.SingScores = Ord(sibRemainingOnly))) then
  begin
    for I := 0 to 2 do
      try
        BestScore[I] := DataBase.ReadMax_ScoreLocal(CurrentSong, I);
        AverageScore[I] := DataBase.ReadMedia_ScoreLocal(CurrentSong, I);
      except
        on E: Exception do begin BestScore[I] := 0; AverageScore[I] := 0; Log.LogWarn(E.Message, 'Document singing highscores'); end;
      end;
    HighscoresReady := true;
  end;
  DocumentUI.SetModel('singing.artist', CurrentSong.Artist);
  DocumentUI.SetModel('singing.title', CurrentSong.Title);
  DocumentUI.SetModel('singing.voices', IntToStr(CurrentSong.VoiceCount), 1);
  SetDocumentNumber('singing.aspect', (ScreenW / Max(1, ScreenH)) / (RenderW / Max(1, RenderH)));
  DocumentUI.SetModel('singing.medley.index', IntToStr(PlaylistMedley.CurrentMedleySong), 1);
  DocumentUI.SetModel('singing.medley.count', IntToStr(PlaylistMedley.NumMedleySongs), 1);
  Bool('medley.active', ScreenSong.Mode = smMedley);
  Bool('avatars', ScreenSing.Settings.AvatarsVisible);
  Bool('scores', ScreenSing.Settings.ScoresVisible and ScreenSing.Scores.Visible);
  Bool('bars', ScreenSing.Scores.RBVisible);
  Bool('ratingFeedback', ScreenSing.Settings.FeedbackVisible and ScreenSing.Scores.Visible);
  Bool('lyrics', ScreenSing.Settings.LyricsVisible);
  Bool('soloText', (not CurrentSong.isDuet) and ScreenSing.Lyrics.HasVisibleText(LyricsState.MidBeat));
  UpperText := false; LowerText := false;
  if CurrentSong.isDuet then
  for I := 0 to High(ScreenSing.DisplayedVoices) do
  begin
    if (ScreenSing.DisplayedVoices[I] < 0) or
      (ScreenSing.DisplayedVoices[I] >= Length(ScreenSing.VoiceLyrics)) then Continue;
    if ScreenSing.DisplayedVoiceBanks[I] = 0 then
    begin
      UpperText := UpperText or ScreenSing.VoiceLyrics[ScreenSing.DisplayedVoices[I]].HasVisibleText(LyricsState.MidBeat);
    end
    else
    begin
      LowerText := LowerText or ScreenSing.VoiceLyrics[ScreenSing.DisplayedVoices[I]].HasVisibleText(LyricsState.MidBeat);
    end;
  end;
  Bool('upperText', UpperText); Bool('lowerText', LowerText);
  Bool('timebar', ScreenSing.Settings.TimeBarVisible);
  Bool('feedback', ScreenSing.Settings.FeedbackVisible);
  Bool('paused', ScreenSing.Paused);
  Bool('video', Assigned(ScreenSing.fCurrentVideo));
  Bool('picture', ScreenSing.fShowBackground);
  Bool('webcam', ScreenSing.fShowWebcam);
  Bool('visualization', ScreenSing.fShowVisualization);
  Bool('messageVisible', MessageVisible and (MessageAlpha > 0));
  Bool('titleVisible', SongTitleVisible and (SongTitleAlpha > 0));
  DocumentUI.SetModel('singing.message', MessageValue);
  SetDocumentNumber('singing.messageAlpha', MessageAlpha);
  DocumentUI.SetModel('singing.songTitle', SongTitleValue);
  SetDocumentNumber('singing.titleAlpha', SongTitleAlpha);
  DocumentUI.SetModel('singing.countdown', IntToStr(CountdownValue), 1);
  SetDocumentNumber('singing.countdownPhase', CountdownPhase);
  DocumentUI.SetModel('singing.scoreMode', IntToStr(Ord(TSingInfoBarMode(EnsureRange(Ini.SingScores, 0, 3)))), 1);
  if Party.bPartyGame and (Ini.SingScores = 0) then DocumentUI.SetModel('singing.scoreMode', '2', 1);
  StartTime := CurrentSong.Start; EndTime := LyricsState.TotalTime;
  if ScreenSong.Mode = smMedley then begin StartTime := ScreenSing.MedleyStart; EndTime := ScreenSing.MedleyEnd; end;
  CurrentTime := LyricsState.GetCurrentTime;
  ClockPosition := CurrentTime; ClockDuration := LyricsState.TotalTime;
  if ScreenSong.Mode = smMedley then
  begin ClockPosition := CurrentTime - ScreenSing.MedleyStart; ClockDuration := ScreenSing.MedleyEnd - ScreenSing.MedleyStart; end;
  ClockPrefix := '';
  case ScreenSing.fTimebarMode of
    tbmRemaining: begin ClockValue := ClockDuration - Max(ClockPosition, CurrentSong.Start); ClockPrefix := '-'; end;
    tbmTotal: begin ClockValue := ClockDuration; ClockPrefix := '#'; end;
    else ClockValue := Max(ClockPosition, CurrentSong.Start);
  end;
  DisplayClock := Format('%s%.2d:%.2d', [ClockPrefix, Round(ClockValue) div 60, Round(ClockValue) mod 60]);
  DocumentUI.SetModel('singing.clock', DisplayClock);
  SetDocumentNumber('singing.position', CurrentTime);
  SetDocumentNumber('singing.start', StartTime);
  SetDocumentNumber('singing.end', EndTime);
  SetDocumentNumber('singing.duration', Max(0.001, EndTime - StartTime));
  SetDocumentNumber('singing.progress', EnsureRange((CurrentTime - StartTime) / Max(0.001, EndTime - StartTime), 0.0, 1.0));
  for I := 0 to PlayersPlay - 1 do
  begin
    Prefix := 'singing.players[' + IntToStr(I) + '].';
    Name := Player[I].Name;
    if Party.bPartyGame then Name := Ini.NameTeam[I];
    DocumentUI.SetModel(Prefix + 'name', Name);
    DocumentUI.SetModel(Prefix + 'voice', IntToStr(Player[I].Track + 1), 1);
    Level := Player[I].Level;
    if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then Level := Ini.Difficulty;
    DocumentUI.SetModel(Prefix + 'level', IntToStr(EnsureRange(Level, 0, 2)), 1);
    Color := GetPlayerColor(Ini.SingColor[I]);
    DocumentUI.SetModel(Prefix + 'color', ColorText(Color));
    ImagePath := DefaultAvatarFile(I).ToUTF8(false);
    if AvatarPlayerTextures[I + 1] <> nil then ImagePath := AvatarPlayerTextures[I + 1].Name.ToUTF8(false);
    DocumentUI.SetModel(Prefix + 'avatar', ImagePath);
    DocumentUI.SetModel(Prefix + 'avatarTint', '#ffffff');
    if (AvatarPlayerTextures[I + 1] = NoAvatarTexture[I + 1]) and Skin.ColorizeDefaultAvatars then
      DocumentUI.SetModel(Prefix + 'avatarTint', ColorText(Color));
    DocumentUI.SetModel(Prefix + 'notesVisible', IntToStr(Ord(ScreenSing.Settings.NotesVisible[I])), 2);
    DocumentUI.SetModel(Prefix + 'inputVisible', IntToStr(Ord(ScreenSing.Settings.OscilloscopeVisible)), 2);
    if I >= ScreenSing.Scores.PlayerCount then Continue;
    ScorePlayer := ScreenSing.Scores.Players[I];
    DocumentUI.SetModel(Prefix + 'enabled', IntToStr(Ord(ScorePlayer.Visible)), 2);
    DocumentUI.SetModel(Prefix + 'barsVisible', IntToStr(Ord(ScorePlayer.RBVisible)), 2);
    DocumentUI.SetModel(Prefix + 'pendingScore', IntToStr(ScreenSing.Scores.PendingPopUpPoints[I]), 1);
    DocumentUI.SetModel(Prefix + 'score', IntToStr(Player[I].ScoreTotalInt), 1);
    DocumentUI.SetModel(Prefix + 'displayedScore', IntToStr(ScorePlayer.ScoreDisplayed), 1);
    DocumentUI.SetModel(Prefix + 'scoreText', Format('%.5d', [ScorePlayer.ScoreDisplayed]));
    SetDocumentNumber(Prefix + 'rating', ScorePlayer.RBTarget);
    SetDocumentNumber(Prefix + 'actual', ScorePlayer.ScoreActual);
    SetDocumentNumber(Prefix + 'remaining', ScorePlayer.RemainingPossibleScore);
    Potential := EnsureRange((ScorePlayer.ScoreActual + ScorePlayer.RemainingPossibleScore) / MAX_SONG_SCORE, 0.0, 1.0);
    SetDocumentNumber(Prefix + 'potential', Potential);
    Level := EnsureRange(Ini.PlayerLevel[I], 0, 2);
    DocumentUI.SetModel(Prefix + 'best', IntToStr(BestScore[Level]), 1);
    DocumentUI.SetModel(Prefix + 'average', IntToStr(AverageScore[Level]), 1);
  end;
  Lifetime := ScreenSing.Scores.Settings.Phase1Time + ScreenSing.Scores.Settings.Phase2Time + ScreenSing.Scores.Settings.Phase3Time;
  I := 0;
  while I < Length(DocumentNotices) do
    if SDL_GetTicks - DocumentNotices[I].Started > Lifetime then
    begin
      for J := I to High(DocumentNotices) - 1 do DocumentNotices[J] := DocumentNotices[J + 1];
      SetLength(DocumentNotices, Length(DocumentNotices) - 1);
    end
    else Inc(I);
  DocumentUI.SetArray('singing.notices', Length(DocumentNotices));
  for I := 0 to High(DocumentNotices) do
  begin
    Prefix := 'singing.notices[' + IntToStr(I) + '].';
    Age := (SDL_GetTicks - DocumentNotices[I].Started) / 1000;
    DocumentUI.SetModel(Prefix + 'player', IntToStr(DocumentNotices[I].PlayerIndex), 1);
    DocumentUI.SetModel(Prefix + 'rating', IntToStr(DocumentNotices[I].Rating), 1);
    DocumentUI.SetModel(Prefix + 'label', RatingKeys[EnsureRange(DocumentNotices[I].Rating, 0, 8)]);
    DocumentUI.SetModel(Prefix + 'gain', IntToStr(DocumentNotices[I].Gain), 1);
    SetDocumentNumber(Prefix + 'age', Age);
    SetDocumentNumber(Prefix + 'lifetime', Max(0.001, Lifetime / 1000));
  end;
end;

procedure TScreenSingView.DrawDocumentCanvases;
var I, Track, Spacing: integer; Bounds, Guide, Anchor, NoteSize: TDocumentRegion;
    Engine: TLyricEngine; Position: TThemePosition;
begin
  if CurrentSong.isDuet then
  begin
    ScreenSing.LayoutVoiceLyrics;
    EnsureDocumentVoices;
    if ScreenSing.Settings.LyricsVisible then
      for I := 0 to High(ScreenSing.DisplayedVoices) do
      begin
        PositionDocumentVoice(I);
        Track := ScreenSing.DisplayedVoices[I];
        Engine := ScreenSing.VoiceLyrics[Track];
        Engine.Draw(LyricsState.MidBeat);
        SingDrawLyricHelper(Track, Engine.UpperLineX, Engine.UpperLineW / 2, 0);
      end;
  end
  else if ScreenSing.Settings.LyricsVisible then
  begin
    Engine := ScreenSing.Lyrics;
    if DocumentUI.Region('singing-lyrics-upper', Bounds) then
    begin
      Engine.UpperLineX := Bounds.X; Engine.UpperLineY := Bounds.Y;
      Engine.UpperLineW := Bounds.W; Engine.UpperLineH := Bounds.H;
    end;
    if DocumentUI.Region('singing-lyrics-lower', Bounds) then
    begin
      Engine.LowerLineX := Bounds.X; Engine.LowerLineY := Bounds.Y;
      Engine.LowerLineW := Bounds.W; Engine.LowerLineH := Bounds.H;
    end;
    Engine.UpdateLineMetrics;
    Engine.Draw(LyricsState.MidBeat);
    SingDrawLyricHelper(0, Engine.UpperLineX, Engine.UpperLineW / 2, 0);
  end;
  for I := 0 to PlayersPlay - 1 do
  begin
    if ScreenSing.Settings.OscilloscopeVisible and DocumentUI.Region('singing-input-' + IntToStr(I), Bounds) then
    begin
      Position.X := Round(Bounds.X); Position.Y := Round(Bounds.Y);
      Position.W := Round(Bounds.W); Position.H := Round(Bounds.H); Position.ScaleMode := lsStretch;
      SingDrawOscilloscope(Position, I);
    end;
    if not DocumentUI.Region('singing-notes-' + IntToStr(I), Bounds) then Continue;
    if not DocumentUI.Region('singing-guide-' + IntToStr(I), Guide) then Continue;
    if not DocumentUI.Region('singing-note-anchor-' + IntToStr(I), Anchor) then Continue;
    Spacing := Max(1, Round(Guide.H / 9));
    if DocumentUI.Region('singing-note-size-' + IntToStr(I), NoteSize) then
    begin NotesW[I] := Max(1, NoteSize.W); NotesH[I] := Max(2, NoteSize.H); end;
    if ScreenSing.Settings.InputVisible and ScreenSing.Settings.NotesVisible[I] and (Ini.NoteLines = 1) then
      SingDrawNoteLines(Guide.X, Guide.Y, Guide.X + Guide.W, Spacing);
    Track := Player[I].Track;
    if CurrentSong.isDuet then Engine := ScreenSing.VoiceLyrics[Track] else Engine := ScreenSing.Lyrics;
    if Engine.GetUpperLine.LastLine and not Engine.HasVisibleText(LyricsState.MidBeat) then
    begin
      if Ini.PitchTrace <> 0 then SingDrawPlayerLine(Bounds.X, Anchor.Y, Bounds.W, Track, I, Spacing, true);
      Continue;
    end;
    SingDrawPlayerBGLine(Bounds.X, Anchor.Y, Bounds.X + Bounds.W, Track, I, Spacing);
    SingDrawLine(Bounds.X, Anchor.Y, Bounds.X + Bounds.W, Track, I, Spacing);
    SingDrawPlayerLine(Bounds.X, Anchor.Y, Bounds.W, Track, I, Spacing);
  end;
end;

function BuildSingPlayerTemplate(const PlayerCountOnScreen, PlayerIndexOnScreen: integer): TThemeSingPlayer;
var
  BaseTemplate: TThemeSingPlayer;
  LaneLeft: integer;
  LaneWidth: integer;
  Scale: real;
  FrameW: integer;
  FrameH: integer;
  ScoreW: integer;
  ScoreX: integer;
  NameX: integer;
  NameW: integer;
  NameH: integer;
  GroupTop: integer;
  Layout: TSingLaneLayout;
begin
  BaseTemplate := Theme.Sing.PlayerTemplate;
  Layout := GetSingLaneLayout(PlayerCountOnScreen, PlayerIndexOnScreen, Theme.Sing.PlayerLayout,
    IsCurrentSongDuet);
  GetSingHeaderPlacement(PlayerCountOnScreen, PlayerIndexOnScreen, Layout,
    Theme.Sing.PlayerWidgetLayout, LaneLeft, LaneWidth, GroupTop, Scale, IsCurrentSongDuet);

  FrameW := Max(1, Round(BaseTemplate.AvatarFrame.W * Scale));
  FrameH := Max(1, Round(BaseTemplate.AvatarFrame.H * Scale));
  ScoreW := Max(1, Round(BaseTemplate.ScoreBackground.W * Scale));


  Result := BaseTemplate;
  Result.AvatarFrame.X := GetSingPlayerWidgetX(BaseTemplate.AvatarFrame.X,
    BaseTemplate.AvatarFrame.W, FrameW, LaneLeft, LaneWidth,
    Theme.Sing.PlayerWidgetLayout.AvatarAnchorX, Scale, Theme.Sing.PlayerWidgetLayout);
  Result.AvatarFrame.Y := GetSingPlayerWidgetY(BaseTemplate.AvatarFrame.Y, GroupTop,
    Scale, Theme.Sing.PlayerWidgetLayout);
  Result.AvatarFrame.W := FrameW;
  Result.AvatarFrame.H := FrameH;

  // Round the inset outward against the already rounded frame bounds so a
  // fractional player scale cannot expose a seam beside the avatar.
  Result.Avatar.X := Result.AvatarFrame.X + Floor(
    (BaseTemplate.Avatar.X - BaseTemplate.AvatarFrame.X) * Scale);
  Result.Avatar.Y := Result.AvatarFrame.Y + Floor(
    (BaseTemplate.Avatar.Y - BaseTemplate.AvatarFrame.Y) * Scale);
  Result.Avatar.W := Max(1, Ceil(
    (BaseTemplate.Avatar.X + BaseTemplate.Avatar.W - BaseTemplate.AvatarFrame.X) * Scale) -
    Floor((BaseTemplate.Avatar.X - BaseTemplate.AvatarFrame.X) * Scale));
  Result.Avatar.H := Max(1, Ceil(
    (BaseTemplate.Avatar.Y + BaseTemplate.Avatar.H - BaseTemplate.AvatarFrame.Y) * Scale) -
    Floor((BaseTemplate.Avatar.Y - BaseTemplate.AvatarFrame.Y) * Scale));

  NameH := Max(Theme.Sing.PlayerWidgetLayout.NameMinH, Round(BaseTemplate.Name.H * Scale));
  if BaseTemplate.Name.W > 0 then
    NameW := Max(Theme.Sing.PlayerWidgetLayout.NameMinW, Round(BaseTemplate.Name.W * Scale))
  else
    NameW := Theme.Sing.PlayerWidgetLayout.NameMinW;
  NameX := GetSingPlayerWidgetX(BaseTemplate.Name.X, BaseTemplate.Name.W, NameW,
    LaneLeft, LaneWidth, Theme.Sing.PlayerWidgetLayout.NameAnchorX, Scale,
    Theme.Sing.PlayerWidgetLayout);
  ScoreX := GetSingPlayerWidgetX(BaseTemplate.ScoreBackground.X,
    BaseTemplate.ScoreBackground.W, ScoreW, LaneLeft, LaneWidth,
    Theme.Sing.PlayerWidgetLayout.ScoreAnchorX, Scale, Theme.Sing.PlayerWidgetLayout);
  if BaseTemplate.Name.W <= 0 then
    NameW := Max(Theme.Sing.PlayerWidgetLayout.NameMinW, ScoreX - NameX);
  Result.Name.X := NameX;
  Result.Name.Y := GetSingPlayerWidgetY(BaseTemplate.Name.Y, GroupTop,
    Scale, Theme.Sing.PlayerWidgetLayout);
  Result.Name.W := NameW;
  Result.Name.H := NameH;
  Result.Name.Size := Max(Theme.Sing.PlayerWidgetLayout.NameMinSize, Round(BaseTemplate.Name.Size * Scale));
  if LaneWidth <= 0 then
    Result.Name.W := 0;
end;

procedure ApplySingPlayerTemplate(const SingPlayer: TThemeSingPlayer; FrameSlot, AvatarSlot, TextSlot: integer);
begin
  ScreenSing.Statics[FrameSlot].Texture.X := SingPlayer.AvatarFrame.X;
  ScreenSing.Statics[FrameSlot].Texture.Y := SingPlayer.AvatarFrame.Y;
  ScreenSing.Statics[FrameSlot].Texture.W := SingPlayer.AvatarFrame.W;
  ScreenSing.Statics[FrameSlot].Texture.H := SingPlayer.AvatarFrame.H;
  ScreenSing.Statics[FrameSlot].Texture.Z := SingPlayer.AvatarFrame.Z;
  ScreenSing.Statics[FrameSlot].Texture.Alpha := SingPlayer.AvatarFrame.Alpha;

  ScreenSing.Statics[AvatarSlot].Texture.X := SingPlayer.Avatar.X;
  ScreenSing.Statics[AvatarSlot].Texture.Y := SingPlayer.Avatar.Y;
  ScreenSing.Statics[AvatarSlot].Texture.W := SingPlayer.Avatar.W;
  ScreenSing.Statics[AvatarSlot].Texture.H := SingPlayer.Avatar.H;
  ScreenSing.Statics[AvatarSlot].Texture.Z := SingPlayer.Avatar.Z;
  ScreenSing.Statics[AvatarSlot].Texture.Alpha := SingPlayer.Avatar.Alpha;
  ScreenSing.Statics[AvatarSlot].Texture.CornerRadius := SingPlayer.Avatar.CornerRadius;
  with ScreenSing.Statics[AvatarSlot].Texture do
  begin
    FitLayoutChild(X, Y, W, H,
      SingPlayer.AvatarFrame.X, SingPlayer.AvatarFrame.Y,
      SingPlayer.AvatarFrame.W, SingPlayer.AvatarFrame.H, SingPlayer.AvatarFrame.ScaleMode, 0);
    ScaleMode := lsStretch;
  end;

  ScreenSing.Text[TextSlot].X := SingPlayer.Name.X;
  ScreenSing.Text[TextSlot].Y := SingPlayer.Name.Y;
  ScreenSing.Text[TextSlot].W := SingPlayer.Name.W;
  ScreenSing.Text[TextSlot].H := SingPlayer.Name.H;
  ScreenSing.Text[TextSlot].Z := SingPlayer.Name.Z;
  ScreenSing.Text[TextSlot].Size := SingPlayer.Name.Size;
end;

//ToDo basisbit: check this again
// Dirty HacK
procedure TScreenSingView.SwapToScreen(Screen: integer);
var
  LocalPlayerCount: integer;
  FirstPlayerIndex: integer;
  FrameSlots: TSlotArray;
  AvatarSlots: TSlotArray;
  IterLayoutPlayerCount: integer;
  procedure setVisible(const elements: TSlotArray; visible: boolean);
  var
    J: integer;
  begin
    for J := 0 to High(elements) do
      ScreenSing.Statics[elements[J]].Visible := visible;
  end;
  procedure hide(const elements: TSlotArray);
  begin
    setVisible(elements, false);
  end;
  procedure maybeShowCount(const elements: TSlotArray; Count: integer);
  var
    J: integer;
  begin
    if not ScreenSing.Settings.AvatarsVisible then
      Exit;

    for J := 0 to Count - 1 do
      ScreenSing.Statics[elements[J]].Visible := true;
  end;
  procedure hideGroup(APlayerCount: integer);
  begin
    GetSingWidgetSlots(Self, APlayerCount, FrameSlots, AvatarSlots);
    hide(FrameSlots);
    hide(AvatarSlots);
  end;
  procedure setStaticColor(StaticIndex, PlayerIndex: integer);
  var
    PlayerColor: TRGB;
  begin
    PlayerColor := GetPlayerColor(Ini.SingColor[PlayerIndex]);
    ScreenSing.Statics[StaticIndex].Texture.ColR := PlayerColor.R;
    ScreenSing.Statics[StaticIndex].Texture.ColG := PlayerColor.G;
    ScreenSing.Statics[StaticIndex].Texture.ColB := PlayerColor.B;
  end;
  procedure setVisibleSlotColors(const Slots: TSlotArray; Count, FirstIndex: integer);
  var
    J: integer;
  begin
    for J := 0 to Count - 1 do
      setStaticColor(Slots[J], FirstIndex + J);
  end;
  procedure setVisibleSlotAvatars(const Slots: TSlotArray; Count, FirstIndex: integer);
  var
    J: integer;
    PlayerIndex: integer;
    CurrentTexture: TTexture;
  begin
    for J := 0 to Count - 1 do
    begin
      PlayerIndex := FirstIndex + J + 1;
      if (PlayerIndex >= 1) and (PlayerIndex <= UIni.IMaxPlayerCount) then
      begin
        CurrentTexture := ScreenSing.Statics[Slots[J]].Texture;
        if AvatarPlayerTextures[PlayerIndex] = nil then
          Continue;
        if (DefaultAvatarTexture <> nil) and
          (AvatarPlayerTextures[PlayerIndex] = NoAvatarTexture[PlayerIndex]) then
        begin
          ScreenSing.Statics[Slots[J]].Texture := DefaultAvatarTexture.Clone;
          ScreenSing.Statics[Slots[J]].Texture.ColR := NoAvatarTexture[PlayerIndex].ColR;
          ScreenSing.Statics[Slots[J]].Texture.ColG := NoAvatarTexture[PlayerIndex].ColG;
          ScreenSing.Statics[Slots[J]].Texture.ColB := NoAvatarTexture[PlayerIndex].ColB;
        end
        else
          ScreenSing.Statics[Slots[J]].Texture := AvatarPlayerTextures[PlayerIndex].Clone;
        ScreenSing.Statics[Slots[J]].Texture.X := CurrentTexture.X;
        ScreenSing.Statics[Slots[J]].Texture.Y := CurrentTexture.Y;
        ScreenSing.Statics[Slots[J]].Texture.W := CurrentTexture.W;
        ScreenSing.Statics[Slots[J]].Texture.H := CurrentTexture.H;
        ScreenSing.Statics[Slots[J]].Texture.Z := CurrentTexture.Z;
        ScreenSing.Statics[Slots[J]].Texture.Alpha := CurrentTexture.Alpha;
        ScreenSing.Statics[Slots[J]].Texture.ScaleMode := CurrentTexture.ScaleMode;
        CurrentTexture.Free;
      end;
    end;
  end;
begin
  if DocumentActive then Exit;
  for IterLayoutPlayerCount := 1 to UIni.IMaxPlayerCount do
    hideGroup(IterLayoutPlayerCount);

  if Ini.Screens = 1 then
  begin
    LocalPlayerCount := GetScreenPlayerCount(PlayersPlay, 2, Screen);
    FirstPlayerIndex := GetFirstPlayerIndexForScreen(PlayersPlay, 2, Screen);
  end
  else
  begin
    LocalPlayerCount := PlayersPlay;
    FirstPlayerIndex := 0;
  end;

  GetSingWidgetSlots(Self, LocalPlayerCount, FrameSlots, AvatarSlots);
  setVisibleSlotColors(FrameSlots, LocalPlayerCount, FirstPlayerIndex);
  setVisibleSlotAvatars(AvatarSlots, LocalPlayerCount, FirstPlayerIndex);
  maybeShowCount(FrameSlots, LocalPlayerCount);
  maybeShowCount(AvatarSlots, LocalPlayerCount);

end;

constructor TScreenSingView.Create;
var
  Col: array [1..UIni.IMaxPlayerCount] of TRGB;
  I: integer;
  procedure setColor(var avatarFrame: TThemeStatic; color: TRGB);
  begin
    avatarFrame.ColR := color.R;
    avatarFrame.ColG := color.G;
    avatarFrame.ColB := color.B;
  end;
  // passing the integer for the static by reference is deliberate
  procedure setColorAndAssignAvatarFrameStatic(var avatarFrame: TThemeStatic; var static: integer; color: TRGB);
  begin
    setColor(avatarFrame, color);
    static := ScreenSing.AddStatic(avatarFrame);
  end;
  procedure setColorAndAssignAvatarFrameStaticForSlot(const PlayerCountOnScreen, PlayerIndexOnScreen: integer; var static: integer; color: TRGB);
  var
    SingPlayer: TThemeSingPlayer;
  begin
    SingPlayer := BuildSingPlayerTemplate(PlayerCountOnScreen, PlayerIndexOnScreen);
    setColorAndAssignAvatarFrameStatic(SingPlayer.AvatarFrame, static, color);
  end;
  // passing the integers for the statics by reference is deliberate
  procedure setColorAndAssignStatics(var singPlayer: TThemeSingPlayer; var avatarFrameStatic: integer; var nameStatic: integer; color: TRGB);
  begin
    setColorAndAssignAvatarFrameStatic(singPlayer.AvatarFrame, avatarFrameStatic, color);
    nameStatic := ScreenSing.AddText(singPlayer.Name);
  end;
  procedure setColorAndAssignStaticsForSlot(const PlayerCountOnScreen, PlayerIndexOnScreen: integer; var avatarFrameStatic: integer; var nameStatic: integer; color: TRGB);
  var
    SingPlayer: TThemeSingPlayer;
  begin
    SingPlayer := BuildSingPlayerTemplate(PlayerCountOnScreen, PlayerIndexOnScreen);
    setColorAndAssignStatics(SingPlayer, avatarFrameStatic, nameStatic, color);
  end;
  // passing the integer for the static by reference is deliberate
  procedure assignAvatarStatic(var singPlayer: TThemeSingPlayer; var avatarStatic: integer; var texture: TTexture);
  begin
    avatarStatic := ScreenSing.AddStaticAlphaRectangle(singPlayer.Avatar);
    if (texture <> nil) then
    begin
      ScreenSing.Statics[avatarStatic].Texture.Free;
      ScreenSing.Statics[avatarStatic].Texture := texture.Clone;
    end;
    ScreenSing.Statics[avatarStatic].Texture.X := singPlayer.Avatar.X;
    ScreenSing.Statics[avatarStatic].Texture.Y := singPlayer.Avatar.Y;
    ScreenSing.Statics[avatarStatic].Texture.H := singPlayer.Avatar.H;
    ScreenSing.Statics[avatarStatic].Texture.W := singPlayer.Avatar.W;
    ScreenSing.Statics[avatarStatic].Texture.Z := singPlayer.Avatar.Z;
    ScreenSing.Statics[avatarStatic].Texture.Alpha := singPlayer.Avatar.Alpha;
    ScreenSing.Statics[avatarStatic].Texture.CornerRadius := singPlayer.Avatar.CornerRadius;
    ScreenSing.Statics[avatarStatic].Texture.ScaleMode := singPlayer.Avatar.ScaleMode;
  end;
  procedure assignAvatarStaticForSlot(const PlayerCountOnScreen, PlayerIndexOnScreen: integer; var avatarStatic: integer; var texture: TTexture);
  var
    SingPlayer: TThemeSingPlayer;
  begin
    SingPlayer := BuildSingPlayerTemplate(PlayerCountOnScreen, PlayerIndexOnScreen);
    assignAvatarStatic(SingPlayer, avatarStatic, texture);
  end;
  procedure InitFrameSlots(MinLayoutPlayerCount, MaxLayoutPlayerCount: integer; CreateTextSlots: boolean);
  var
    LayoutPlayerCount: integer;
    SlotIndex: integer;
    ColorIndex: integer;
  begin
    for LayoutPlayerCount := MinLayoutPlayerCount to MaxLayoutPlayerCount do
    begin
      for SlotIndex := 0 to LayoutPlayerCount - 1 do
      begin
        ColorIndex := (SlotIndex mod UIni.IMaxPlayerCount) + 1;
        if CreateTextSlots then
          setColorAndAssignStaticsForSlot(LayoutPlayerCount, SlotIndex,
            PlayerFrameSlots[LayoutPlayerCount, SlotIndex],
            PlayerTextSlots[LayoutPlayerCount, SlotIndex],
            Col[ColorIndex])
        else
          setColorAndAssignAvatarFrameStaticForSlot(LayoutPlayerCount, SlotIndex,
            PlayerFrameSlots[LayoutPlayerCount, SlotIndex],
            Col[ColorIndex]);
      end;
    end;
  end;
  procedure InitAvatarSlots(MaxLayoutPlayerCount: integer);
  var
    LayoutPlayerCount: integer;
    SlotIndex: integer;
    PlayerIndex: integer;
  begin
    for LayoutPlayerCount := 1 to MaxLayoutPlayerCount do
    begin
      for SlotIndex := 0 to LayoutPlayerCount - 1 do
      begin
        PlayerIndex := (SlotIndex mod UIni.IMaxPlayerCount) + 1;
        assignAvatarStaticForSlot(LayoutPlayerCount, SlotIndex,
          PlayerAvatarSlots[LayoutPlayerCount, SlotIndex],
          AvatarPlayerTextures[PlayerIndex]);
        if (DefaultAvatarTexture <> nil) and
          (AvatarPlayerTextures[PlayerIndex] = NoAvatarTexture[PlayerIndex]) then
        begin
          with ScreenSing.Statics[PlayerAvatarSlots[LayoutPlayerCount, SlotIndex]] do
          begin
            Texture.Free;
            Texture := DefaultAvatarTexture.Clone;
            Texture.ColR := NoAvatarTexture[PlayerIndex].ColR;
            Texture.ColG := NoAvatarTexture[PlayerIndex].ColG;
            Texture.ColB := NoAvatarTexture[PlayerIndex].ColB;
          end;
        end;
      end;
    end;
  end;
begin
  DocumentUI := TDocumentUI.Open(uiSingingScreen);
  DocumentPlayerCount := -1;
  if DocumentUI <> nil then
  begin
    lastVolume := -1;
    ScreenSing.RightMbESC := false;
    ScreenSing.fShowVisualization := false;
    ScreenSing.fShowWebcam := false;
    ScreenSing.fShowBackground := false;
    ScreenSing.fCurrentVideo := nil;
    GapCountdown := TGapCountdown.Create;
    ScreenSing.Scores := TSingScores.Create;
    ScreenSing.Scores.LoadfromTheme;
    LoadSingScreenTextures(true);
    ScreenSing.Lyrics := TLyricEngine.Create(0, 0, 1, 1, 0, 0, 1, 1);
    ScreenSing.fLyricsSync := TLyricsSyncSource.Create;
    ScreenSing.fMusicSync := TMusicSyncSource.Create;
    ScreenSing.eSongLoaded := THookableEvent.Create('ScreenSing.SongLoaded');
    ResetHUD;
    Exit;
  end;
  lastVolume:= -1;
  //too dangerous, a mouse button is quickly pressed by accident
  ScreenSing.RightMbESC := false;

  ScreenSing.fShowVisualization := false;
  ScreenSing.fShowWebcam := false;
  ScreenSing.fShowBackground := false;

  ScreenSing.fCurrentVideo := nil;

  // create score class
  GapCountdown := TGapCountdown.Create;
  ScreenSing.Scores := TSingScores.Create;
  ScreenSing.Scores.LoadfromTheme;

  ScreenSing.LoadFromTheme(Theme.Sing);

  // lyrics bar
  StaticLyricsBar := ScreenSing.AddStatic(Theme.Sing.StaticLyricsBar);
  StaticLyricsBarDuet := ScreenSing.AddStatic(Theme.Sing.StaticLyricsBarDuet);

  {SetLength(StaticDuet, Length(Theme.Sing.StaticDuet));
  for i := 0 to High(StaticDuet) do
    StaticDuet[i] := ScreenSing.AddStatic(Theme.Sing.StaticDuet[i]);}

  // timebar
  StaticTimeBar := ScreenSing.AddStatic(Theme.Sing.StaticTimeBar);
  StaticTimeProgress := ScreenSing.AddStaticColorRectangle(Theme.Sing.StaticTimeProgress);
  TextTimeLabelText := ScreenSing.AddText(Theme.Sing.TextTimeLabelText);
  TextTimeText := ScreenSing.AddText(Theme.Sing.TextTimeText);

  for I := 1 to UIni.IMaxPlayerCount do
    Col[I] := GetPlayerColor(Ini.SingColor[I - 1]);

  InitFrameSlots(1, UIni.IMaxPlayerCount, true);

  for I := 1 to PlayersPlay do
  begin
    if (Party.bPartyGame) then
    begin
      ScreenSing.PlayerNames[I] := Ini.NameTeam[I-1];
    end
    else
    begin
      ScreenSing.PlayerNames[I] := Player[I-1].Name;
    end;
    ScreenSing.PlayerDuetNames[I] := ScreenSing.PlayerNames[I];
  end;

  LoadSingScreenTextures(true);

  StaticPausePopup := ScreenSing.AddStatic(Theme.Sing.PausePopUp);

  // <note> pausepopup is not visible at the beginning </note>
  ScreenSing.Statics[StaticPausePopup].Visible := false;

  ScreenSing.Lyrics := TLyricEngine.Create(
      Theme.LyricBar.UpperX, Theme.LyricBar.UpperY, Theme.LyricBar.UpperW, Theme.LyricBar.UpperH,
      Theme.LyricBar.LowerX, Theme.LyricBar.LowerY, Theme.LyricBar.LowerW, Theme.LyricBar.LowerH);

  ScreenSing.fLyricsSync := TLyricsSyncSource.Create();
  ScreenSing.fMusicSync := TMusicSyncSource.Create();

  SongNameStatic := ScreenSing.AddStatic(Theme.Sing.StaticSongName);;
  SongNameText := ScreenSing.AddText(Theme.Sing.TextSongName);

  ScreenSing.eSongLoaded := THookableEvent.Create('ScreenSing.SongLoaded');

  // Info Message
  ScreenSing.InfoMessageBG := ScreenSing.AddStatic(Theme.Sing.InfoMessageBG);
  ScreenSing.InfoMessageText := ScreenSing.AddText(Theme.Sing.InfoMessageText);

  if Theme.Sing.HasLanePanel then
  begin
    I := ScreenSing.AddStatic(Theme.Sing.LanePanel);
    LanePanelTexture := ScreenSing.Statics[I].Texture.Clone;
    ScreenSing.Statics[I].Visible := false;
    LanePanelTexture.ScaleMode := lsStretch;
  end;

  if Theme.Sing.HasHeader then
  begin
    I := ScreenSing.AddStatic(Theme.Sing.Header);
    HeaderTexture := ScreenSing.Statics[I].Texture.Clone;
    ScreenSing.Statics[I].Visible := false;
  end;
  if Theme.Sing.DefaultAvatarTex <> '' then
    DefaultAvatarTexture := Renderer.LoadTexture(Skin.GetTextureFileName(Theme.Sing.DefaultAvatarTex),
      TEXTURE_TYPE_TRANSPARENT, 0);
  InitAvatarSlots(UIni.IMaxPlayerCount);
end;

destructor TScreenSingView.Destroy;
begin
  DefaultAvatarTexture.Free;
  HeaderTexture.Free;
  LanePanelTexture.Free;
  GapCountdown.Free;
  DocumentUI.Free;
  UnloadSingScreenTextures;
  inherited;
end;

procedure TScreenSingView.DrawHeaders;
var I, Count, LocalIndex, Left, Width, Top: integer;
  Scale: real;
  Lane: TSingLaneLayout;
begin
  if (HeaderTexture = nil) or not (ScreenSing.Settings.AvatarsVisible or
    ScreenSing.Settings.ScoresVisible) then Exit;
  Count := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
  for I := 0 to PlayersPlay - 1 do
  begin
    if GetPlayerScreen(I, PlayersPlay, Screens) <> ScreenAct then Continue;
    LocalIndex := GetPlayerIndexOnScreen(I, PlayersPlay, Screens);
    Lane := GetSingLaneLayout(Count, LocalIndex, Theme.Sing.PlayerLayout, IsCurrentSongDuet);
    GetSingHeaderPlacement(Count, LocalIndex, Lane, Theme.Sing.PlayerWidgetLayout,
      Left, Width, Top, Scale, IsCurrentSongDuet);
    HeaderTexture.X := GetSingPlayerWidgetX(Theme.Sing.Header.X, Theme.Sing.Header.W,
      Round(Theme.Sing.Header.W * Scale), Left, Width, 0, Scale, Theme.Sing.PlayerWidgetLayout);
    HeaderTexture.Y := GetSingPlayerWidgetY(Theme.Sing.Header.Y, Top, Scale, Theme.Sing.PlayerWidgetLayout);
    HeaderTexture.W := Theme.Sing.Header.W * Scale;
    HeaderTexture.H := Theme.Sing.Header.H * Scale;
    Renderer.DrawTexture(HeaderTexture);
  end;
end;

procedure TScreenSingView.DrawLanePanels;
var
  PlayerIndex, Count, LocalIndex: integer;
  Layout: TSingLaneLayout;
  Padding: single;
  Col: TRGB;
begin
  if LanePanelTexture = nil then Exit;
  Count := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    if GetPlayerScreen(PlayerIndex, PlayersPlay, Screens) <> ScreenAct then Continue;
    if not ScreenSing.Settings.NotesVisible[PlayerIndex] then Continue;
    LocalIndex := GetPlayerIndexOnScreen(PlayerIndex, PlayersPlay, Screens);
    Layout := GetSingLaneLayout(Count, LocalIndex, Theme.Sing.PlayerLayout, CurrentSong.isDuet);
    Padding := Theme.Sing.LanePanelPadding * Layout.ContentScale;
    LanePanelTexture.X := Layout.GridLeft - Padding;
    LanePanelTexture.Y := Layout.GuideTopY - Padding;
    LanePanelTexture.W := Layout.GridWidth + 2 * Padding;
    LanePanelTexture.H := 9 * Layout.NoteLineSpacing + 2 * Padding;
    LanePanelTexture.Z := Theme.Sing.LanePanel.Z;
    Renderer.DrawTexture(LanePanelTexture);
    if Theme.Sing.LaneAccentWidth > 0 then
    begin
      Col := GetPlayerColor(Ini.SingColor[PlayerIndex]);
      Renderer.DrawQuad(LanePanelTexture.X + 1, LanePanelTexture.Y + 8 * Layout.ContentScale,
        0, Theme.Sing.LaneAccentWidth * Layout.ContentScale,
        Max(1, LanePanelTexture.H - 16 * Layout.ContentScale), Col.R, Col.G, Col.B, 1);
    end;
  end;
end;

function TScreenSingView.Draw: boolean;
var
  DisplayTime:            real;
  DisplayPrefix:          string;
  DisplayMin:             integer;
  DisplaySec:             integer;
  CurLyricsTime:          real;
  VideoFrameTime:         Extended;
  ScorePlayerIndex:       integer;
  VoiceIndex:             integer;
  medley_end:             boolean;
  medley_start_applause:  boolean;
  LocalPlayerCount:       integer;
  LocalStartIndex:        integer;
  FrameSlots:             TSlotArray;
  AvatarSlots:            TSlotArray;
  TextSlots:              TSlotArray;
  FrameWasVisible:        array [0..UIni.IMaxPlayerCount-1] of boolean;
  AvatarWasVisible:       array [0..UIni.IMaxPlayerCount-1] of boolean;
  IterLayoutPlayerCount:  integer;
  SlotIndex:              integer;
  SingPlayer:             TThemeSingPlayer;
  DrawScorePanel:         boolean;
  ScoreMode:              TSingInfoBarMode;
  function ScoringFinished(TrackIndex: integer): boolean;
  begin
    Result := (CurrentSong.Tracks[TrackIndex].HighestScoredBeat = Low(Integer)) or
      (CurLyricsTime >= GetTimeFromBeat(CurrentSong.Tracks[TrackIndex].HighestScoredBeat));
  end;
  procedure SetPlayerNameTexts(const Slots: TSlotArray; FirstPlayerIndex: integer; UseDuetNames: boolean);
  var
    J: integer;
    PlayerIndex: integer;
  begin
    for J := 0 to High(Slots) do
    begin
      PlayerIndex := FirstPlayerIndex + J;
      if (PlayerIndex >= 1) and (PlayerIndex <= PlayersPlay) then
      begin
        if UseDuetNames then
          ScreenSing.Text[Slots[J]].Text := ScreenSing.PlayerDuetNames[PlayerIndex]
        else
          ScreenSing.Text[Slots[J]].Text := ScreenSing.PlayerNames[PlayerIndex];
      end
      else
      begin
        ScreenSing.Text[Slots[J]].Text := '';
      end;
    end;
  end;
  procedure SetTextVisibility(const Slots: TSlotArray; VisibleCount: integer; Visible: boolean);
  var
    J: integer;
  begin
    for J := 0 to High(Slots) do
      ScreenSing.Text[Slots[J]].Visible := Visible and (J < VisibleCount) and
        ScreenSing.Settings.AvatarsVisible and Theme.Sing.PlayerTemplate.NameEnabled;
  end;
  procedure HidePlayerAvatarsForScorePanel;
  var
    J: integer;
  begin
    GetSingWidgetSlots(Self, LocalPlayerCount, FrameSlots, AvatarSlots);
    for J := 0 to LocalPlayerCount - 1 do
    begin
      FrameWasVisible[J] := ScreenSing.Statics[FrameSlots[J]].Visible;
      AvatarWasVisible[J] := ScreenSing.Statics[AvatarSlots[J]].Visible;
      ScreenSing.Statics[FrameSlots[J]].Visible := false;
      ScreenSing.Statics[AvatarSlots[J]].Visible := false;
    end;
  end;
  procedure DrawPlayerAvatarsAfterScorePanel;
  var
    J: integer;
  begin
    for J := 0 to LocalPlayerCount - 1 do
    begin
      ScreenSing.Statics[FrameSlots[J]].Visible := FrameWasVisible[J];
      ScreenSing.Statics[AvatarSlots[J]].Visible := AvatarWasVisible[J];
      ScreenSing.Statics[FrameSlots[J]].Draw;
      ScreenSing.Statics[AvatarSlots[J]].Draw;
    end;
  end;
begin
  CountdownValue := 0;
  if DocumentUI = nil then ScreenSing.Background.Draw
  else
  begin
    SyncDocumentHUD;
    DocumentUI.PrepareLayout;
    // Reset the render target before drawing native media into the document stage.
    if not TMenuBackground.SuppressDrawing then
    begin
      Renderer.SetClearColor(0, 0, 0, 1);
      Renderer.ClearFrameBuffer(CLEAR_COLOR or CLEAR_DEPTH);
    end;
    if IsCurrentSongDuet then
    begin
      ScreenSing.LayoutVoiceLyrics;
      EnsureDocumentVoices;
    end;
  end;

  // sound enabled/disabled (Party plugins)
  if not(ScreenSing.Settings.SoundEnabled) and not(lastVolume=0) then
  begin
    AudioPlayback.SetVolume(0);
    lastVolume:=0;
  end
  else if not(lastVolume=1) and not(lastVolume=0) then
  begin //changing volume is slow, so do not reset volume every frame
    AudioPlayback.SetVolume(1);
    lastVolume:=1;
  end;

  // swap static textures to current screen ones
  if DocumentUI = nil then SwapToScreen(ScreenAct);

  // draw background picture (if any, and if no visualizations)
  // when we don't check for visualizations the visualizations would
  // be overdrawn by the picture when {UNDEFINED UseTexture} in UVisualizer
  //if (not fShowVisualization) then
  if (not ScreenSing.fShowVisualization) or (ScreenSing.fShowBackground) then
    SingDrawBackground;

  if (ScreenSing.fShowWebCam) then
    SingDrawWebCamFrame;

  LocalPlayerCount := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
  LocalStartIndex := GetFirstPlayerIndexForScreen(PlayersPlay, Screens, ScreenAct) + 1;

  if DocumentUI = nil then
  begin
  for IterLayoutPlayerCount := 1 to UIni.IMaxPlayerCount do
  begin
    GetSingTextSlots(Self, IterLayoutPlayerCount, TextSlots);
    SetTextVisibility(TextSlots, 0, false);
  end;

  GetSingTextSlots(Self, LocalPlayerCount, TextSlots);
  for SlotIndex := 0 to LocalPlayerCount - 1 do
  begin
    SingPlayer := BuildSingPlayerTemplate(LocalPlayerCount, SlotIndex);
    ApplySingPlayerTemplate(
      SingPlayer,
      PlayerFrameSlots[LocalPlayerCount, SlotIndex],
      PlayerAvatarSlots[LocalPlayerCount, SlotIndex],
      PlayerTextSlots[LocalPlayerCount, SlotIndex]
    );
  end;
  SetPlayerNameTexts(TextSlots, LocalStartIndex, IsCurrentSongDuet and (LocalPlayerCount >= 3));
  SetTextVisibility(TextSlots, LocalPlayerCount, true);

  end
  else EnsureDocumentPlayers;

  // Voice colors remain stable when players choose or share voices.

  // retrieve current lyrics time, we have to store the value to avoid
  // that min- and sec-values do not match
  if ScreenSong.Mode = smMedley then
  begin
    CurLyricsTime := LyricsState.GetCurrentTime() - ScreenSing.MedleyStart;
    TotalTime := ScreenSing.MedleyEnd - ScreenSing.MedleyStart;
  end
  else
  begin
    CurLyricsTime := LyricsState.GetCurrentTime();
    TotalTime :=  LyricsState.TotalTime;
  end;

  // retrieve time for timebar text
  case (ScreenSing.fTimebarMode) of
    tbmRemaining: begin
      DisplayTime := TotalTime - Max(CurLyricsTime, CurrentSong.Start);
      DisplayPrefix := '-';
    end;
    tbmTotal: begin
      DisplayTime := TotalTime;
      DisplayPrefix := '#';
    end;
    else begin       // current time
      DisplayTime := Max(CurLyricsTime, CurrentSong.Start);
      DisplayPrefix := '';
    end;
  end;
  DisplayMin := Round(DisplayTime) div 60;
  DisplaySec := Round(DisplayTime) mod 60;

  DisplayClock := Format('%s%.2d:%.2d', [DisplayPrefix, DisplayMin, DisplaySec]);
  if DocumentUI = nil then
  begin
  // update static menu with time ...
  ScreenSing.Text[TextTimeLabelText].Visible := ScreenSing.Settings.TimeBarVisible and
    (Theme.Sing.TextTimeLabelText.Size > 0);
  ScreenSing.Text[TextTimeText].Text := Format('%s%.2d:%.2d', [DisplayPrefix, DisplayMin, DisplaySec]);
  if Theme.Sing.TimeShowTitle then
    ScreenSing.Text[TextTimeText].Text := CurrentSong.Title + '   ' + ScreenSing.Text[TextTimeText].Text;
  ScreenSing.Text[TextTimeText].Visible := ScreenSing.Settings.TimeBarVisible;

  end;

  // Only voices actually assigned to players determine scoring completion.
  if not ScreenSing.SungToEnd then
  begin
    if not CurrentSong.isDuet then
      ScreenSing.SungToEnd := ScoringFinished(0)
    else
    begin
      ScreenSing.SungToEnd := true;
      for ScorePlayerIndex := 0 to PlayersPlay - 1 do
        if not ScoringFinished(Player[ScorePlayerIndex].Track) then
          ScreenSing.SungToEnd := false;
    end;
  end;

  // for medley-mode:
  CurLyricsTime := LyricsState.GetCurrentTime();
  if (ScreenSong.Mode = smMedley) and (CurLyricsTime > ScreenSing.MedleyEnd) then
    medley_end := true
  else
    medley_end := false;

  if (ScreenSong.Mode = smMedley) and (CurLyricsTime >
    GetTimeFromBeat(CurrentSong.Medley.EndBeat)) then
    medley_start_applause := true
  else
    medley_start_applause := false;

  // update and draw movie
  // USE FFMPEG
  if not TMenuBackground.SuppressDrawing and Assigned(ScreenSing.fCurrentVideo) and (not ScreenSing.fShowWebcam) then
  begin
    // Just call this once
    // when Screens = 2
    if (ScreenAct = 1) then
    begin
      if (ScreenSing.ShowFinish) then
      begin
        // everything is setup, determine the current position
        VideoFrameTime := CurrentSong.VideoGAP + Max(LyricsState.GetCurrentTime(), CurrentSong.Start);
      end
      else
      begin
        // Important: do not yet start the triggered timer by a call to
        // LyricsState.GetCurrentTime()
        VideoFrameTime := CurrentSong.VideoGAP;
      end;
      try
        ScreenSing.fCurrentVideo.GetFrame(VideoFrameTime);
      except
      end;
    end;

    if DocumentUI <> nil then PositionDocumentVideo;
    ScreenSing.fCurrentVideo.SetScreen(ScreenAct);
    ScreenSing.fCurrentVideo.Draw;
  end;

  ScoreMode := TSingInfoBarMode(EnsureRange(Ini.SingScores, 0, Ord(High(TSingInfoBarMode))));
  if Party.bPartyGame and (ScoreMode = sibOff) then
    ScoreMode := sibRatingOnly;
  ScreenSing.Scores.SetInfoBarMode(ScoreMode);
  DrawScorePanel := ScreenSing.Settings.ScoresVisible and (ScoreMode <> sibOff);
  if DrawScorePanel and (DocumentUI = nil) then
    HidePlayerAvatarsForScorePanel;

  if DocumentUI = nil then
  begin
  // Match both themed lyric banks to every visible voice, including last-line fades.
  if IsCurrentSongDuet then
  begin
    ScreenSing.LayoutVoiceLyrics;
    ScreenSing.Statics[StaticLyricsBar].Visible := false;
    ScreenSing.Statics[StaticLyricsBarDuet].Visible := false;
    if ScreenSing.Settings.LyricsVisible then
      for VoiceIndex := 0 to High(ScreenSing.DisplayedVoices) do
        if ScreenSing.VoiceLyrics[ScreenSing.DisplayedVoices[VoiceIndex]].HasVisibleText(LyricsState.MidBeat) then
        begin
          if ScreenSing.DisplayedVoiceBanks[VoiceIndex] = 0 then
            ScreenSing.Statics[StaticLyricsBar].Visible := true
          else ScreenSing.Statics[StaticLyricsBarDuet].Visible := true;
        end;
  end
  else
  begin
    ScreenSing.Statics[StaticLyricsBar].Visible := ScreenSing.Settings.LyricsVisible and
      ScreenSing.Lyrics.HasVisibleText(LyricsState.MidBeat);
    ScreenSing.Statics[StaticLyricsBarDuet].Visible := false;
  end;
  ScreenSing.Statics[StaticTimeBar].Visible := ScreenSing.Settings.TimeBarVisible;
  ScreenSing.Statics[StaticTimeProgress].Visible := ScreenSing.Settings.TimeBarVisible;

  // Optional panels use the same lanes and visibility as normal note drawing.
  DrawLanePanels;
  DrawHeaders;

  // draw static menu (FG)
  ScreenSing.DrawFG;

  end
  else
  begin
    SyncDocumentHUD;
    DocumentUI.Draw(true);
  end;

  //Medley Countdown
  if ScreenSong.Mode = smMedley then
    DrawMedleyCountdown;
  if ScreenSing.CountIn then
    DrawCountIn
  else
    DrawGapCountdown;

  // check for music finish
  //Log.LogError('Check for music finish: ' + BoolToStr(Music.Finished) + ' ' + FloatToStr(LyricsState.CurrentTime*1000) + ' ' + IntToStr(CurrentSong.Finish));
  if ScreenSing.ShowFinish then
  begin
    if (not ScreenSing.FinishedMusic) and (not medley_end or (ScreenSong.Mode <> smMedley)) and
       ((CurrentSong.Finish = 0) or
        (LyricsState.GetCurrentTime() * 1000 <= CurrentSong.Finish)) and
       (not ScreenSing.Settings.Finish) then
    begin
      // analyze song if not paused
      if (not ScreenSing.Paused) then
      begin
        Sing(ScreenSing);

        //Update Medley Stats
        if (ScreenSong.Mode = smMedley) and not ScreenSing.FadeOut then
          ScreenSing.UpdateMedleyStats(medley_start_applause);

        Party.CallOnSing;
      end;
    end
    else
    begin
      if not ScreenSing.ContinueDelayedScoring and
        (((not ScreenSing.FadeOut) and (Screens=1)) or (ScreenAct=2)) then
      begin
        ScreenSing.Finish;
      end;
    end;
  end;

  // draw info lyric bar if not medley
  if (ScreenSing.Settings.TimeBarVisible) then
    DrawInfoLyricBar;

  // draw scores
  if DrawScorePanel or ScreenSing.Settings.FeedbackVisible then
  begin
    // Keep popup/score animation state advancing even when its rendering is hidden.
    if DocumentUI = nil then
    begin
      ScreenSing.Scores.Draw(DrawScorePanel, ScreenSing.Settings.FeedbackVisible);
      if DrawScorePanel then DrawPlayerAvatarsAfterScorePanel;
    end
    else ScreenSing.Scores.Draw(false, false);
  end;

  if DocumentUI = nil then SingDraw
  else DrawDocumentCanvases;

  // goldennotestarstwinkle
  if (PlayersPlay > 0) and ScreenSing.Settings.FeedbackVisible then GoldenRec.SpawnRec;

  FadeMessage();
  if DocumentUI <> nil then
  begin
    SyncDocumentHUD;
    DocumentUI.Draw(false, true);
  end;

  // draw pausepopup
  // FIXME: this is a workaround that the static is drawn over the lyrics, lines, scores and effects
  // maybe someone could find a better solution
  if ScreenSing.Paused then
  begin
    if DocumentUI = nil then
    begin
    ScreenSing.Statics[StaticPausePopup].Texture.Z := 1;
    ScreenSing.Statics[StaticPausePopup].Visible := true;
    ScreenSing.Statics[StaticPausePopup].Draw;
    ScreenSing.Statics[StaticPausePopup].Visible := false;
    end;
    SDL_Delay(33);//wait a bit to save electricity...
  end;

  Result := true;
end;

procedure TScreenSingView.DrawMedleyCountdown();
begin
  if AudioPlayback.Position < GetTimeFromBeat(CurrentSong.Medley.StartBeat) then
  begin
    ScreenSing.TextMedleyFadeOut := false;

    if DocumentUI <> nil then begin SongTitleVisible := true; SongTitleAlpha := 1; end
    else
    begin
    ScreenSing.Statics[SongNameStatic].Texture.Alpha := 1;
    ScreenSing.Text[SongNameText].Alpha := 1;

    ScreenSing.Statics[SongNameStatic].Visible := true;
    ScreenSing.Text[SongNameText].Visible := true;
    end;
    DrawCountdown(GetTimeFromBeat(CurrentSong.Medley.StartBeat) - AudioPlayback.Position);
  end else
  begin
    if (ScreenSing.TextMedleyFadeOut = false) then
    begin
      ScreenSing.TextMedleyFadeOut := true;
      ScreenSing.TextMedleyFadeTime := SDL_GetTicks();
    end;

    MedleyTitleFadeOut;
  end;
end;

procedure TScreenSingView.PrepareGapCountdown;
var Track, Line, Note: integer; StartTime, EndTime: double;
begin
  GapCountdown.Clear;
  for Track := 0 to High(CurrentSong.Tracks) do
    for Line := 0 to High(CurrentSong.Tracks[Track].Lines) do
      for Note := 0 to High(CurrentSong.Tracks[Track].Lines[Line].Notes) do
        with CurrentSong.Tracks[Track].Lines[Line].Notes[Note] do
        begin
          StartTime := GetTimeFromBeat(StartBeat);
          EndTime := GetTimeFromBeat(StartBeat + Duration);
          if ScreenSong.Mode = smMedley then
          begin
            StartTime := Max(StartTime, GetTimeFromBeat(CurrentSong.Medley.StartBeat));
            EndTime := Min(EndTime, GetTimeFromBeat(CurrentSong.Medley.EndBeat));
          end;
          GapCountdown.Add(StartTime, EndTime);
        end;
  GapCountdown.Prepare;
  PrepareDocumentSegments;
end;

procedure TScreenSingView.DrawGapCountdown;
var TimeLeft: double;
begin
  if (Ini.GapCountdown = 0) or not ScreenSing.Settings.LyricsVisible then Exit;
  TimeLeft := GapCountdown.Remaining(LyricsState.GetCurrentTime, Ini.GapCountdown * 5);
  if TimeLeft > 0 then DrawCountdown(TimeLeft);
end;

procedure TScreenSingView.DrawCountIn;
var
  Pos: real;
begin
  Pos := AudioPlayback.Position;
  if (Pos > ScreenSing.FirstNote) then
    ScreenSing.CountIn := false
  else
    DrawCountdown(ScreenSing.FirstNote - Pos);

end;

procedure TScreenSingView.DrawCountdown(timeDiff: real);
var
  t: real;
  w, h: real;
  CountDownText:  UTF8String;
begin
  if not ScreenSing.Settings.FeedbackVisible then Exit;
  t := frac(timeDiff);
  if DocumentUI <> nil then
  begin
    CountdownValue := Round(timeDiff - t + 1);
    CountdownPhase := t;
    Exit;
  end;

  h := Theme.Sing.Countdown.Size*t*ScreenH/RenderH;
  SetFontFamily(Theme.Sing.Countdown.Font);
  SetFontStyle(Theme.Sing.Countdown.Style);
  SetFontItalic(false);
  SetFontSize(h);
  SetFontColor(Theme.Sing.Countdown.ColR, Theme.Sing.Countdown.ColG,
    Theme.Sing.Countdown.ColB, t * Theme.Sing.Countdown.Alpha);
  CountDownText := IntToStr(round(timeDiff - t + 1));
  w := TextWidth(PChar(CountDownText));

  SetFontPos(Theme.Sing.Countdown.X * RenderW / 800 - w/2,
    Theme.Sing.Countdown.Y * RenderH / 600 - h/2);
  PrintText(PChar(CountDownText));

end;

procedure TScreenSingView.WriteMessage(msg: UTF8String);
begin
  ScreenSing.MessageTime := SDL_GetTicks();
  if DocumentUI <> nil then
  begin MessageValue := msg; MessageVisible := true; MessageAlpha := 1; Exit; end;

  ScreenSing.Statics[ScreenSing.InfoMessageBG].Texture.Alpha := 1;
  ScreenSing.Text[ScreenSing.InfoMessageText].Alpha := 1;

  ScreenSing.Statics[ScreenSing.InfoMessageBG].Visible := true;
  ScreenSing.Text[ScreenSing.InfoMessageText].Visible := true;
  ScreenSing.Text[ScreenSing.InfoMessageText].Text := msg;
end;

procedure TScreenSingView.FadeMessage();
var
  factor: real;
begin
  if DocumentUI <> nil then
  begin
    MessageAlpha := EnsureRange(1 - Max(0, (SDL_GetTicks - ScreenSing.MessageTime) / 1000 - MAX_MESSAGE) / 2, 0.0, 1.0);
    Exit;
  end;
  if ((SDL_GetTicks - ScreenSing.MessageTime)/1000 > MAX_MESSAGE) then
  begin
    if (ScreenSing.MessageTimeFade = 0) then
      ScreenSing.MessageTimeFade := SDL_GetTicks();

    factor := (SDL_GetTicks - ScreenSing.MessageTimeFade)/1000/2;

    ScreenSing.Statics[ScreenSing.InfoMessageBG].Texture.Alpha := 1 - factor;
    ScreenSing.Text[ScreenSing.InfoMessageText].Alpha := 1 - factor;
  end
  else
    ScreenSing.MessageTimeFade := 0;

  ScreenSing.Statics[ScreenSing.InfoMessageBG].Draw;
  ScreenSing.Text[ScreenSing.InfoMessageText].Draw;
end;

procedure TScreenSingView.CloseMessage();
begin
  if DocumentUI <> nil then begin MessageVisible := false; Exit; end;
  ScreenSing.Statics[ScreenSing.InfoMessageBG].Visible := false;
  ScreenSing.Text[ScreenSing.InfoMessageText].Visible := false;
end;

procedure TScreenSingView.MedleyTitleFadeOut();
var
  Alpha: real;
  CTime: cardinal;
begin

  CTime := SDL_GetTicks() - ScreenSing.TextMedleyFadeTime;
  Alpha := CTime/3000;

  if DocumentUI <> nil then
  begin SongTitleAlpha := EnsureRange(1 - Alpha, 0.0, 1.0); SongTitleVisible := Alpha < 1; Exit; end;
  if (Alpha >= 1) then
  begin
    ScreenSing.Statics[SongNameStatic].Visible := false;
    ScreenSing.Text[SongNameText].Visible := false;
  end
  else
  begin
    ScreenSing.Text[SongNameText].Alpha := 1 - Alpha;
    ScreenSing.Statics[SongNameStatic].Texture.Alpha := 1 - Alpha;
  end;
end;

function TScreenSingView.GetLyricColor(Color: integer): TRGB;
begin
  case (Color) of
    1://blue
    begin
      Result.R := 5/255;
      Result.G := 153/255;
      Result.B := 204/255;
    end;
    2: //red
    begin
      Result.R := 230/255;
      Result.G := 0;
      Result.B := 0;
    end;
    3: //green
    begin
      Result.R := 0;
      Result.G := 170/255;
      Result.B := 0;
    end;
    4: //yellow
    begin
      Result.R := 255/255;
      Result.G := 225/255;
      Result.B := 0;
    end;
    5: //orange
    begin
      Result.R := 227/255;
      Result.G := 127/255;
      Result.B := 0;
    end;
    6: //pink
    begin
      Result.R := 255/255;
      Result.G := 0/255;
      Result.B := 130/255;
    end;
    7: //purple
    begin
      Result.R := 180/255;
      Result.G := 0;
      Result.B := 220/255;
    end;
    8: //gold
    begin
      Result.R := 255/255;
      Result.G := 190/255;
      Result.B := 35/255;
    end;
    9: //gray
    begin
      Result.R := 80/255;
      Result.G := 80/255;
      Result.B := 80/255;
    end;
    10: //dark blue
    begin
      Result.R := 90/255;
      Result.G := 90/255;
      Result.B := 240/255;
    end;
    11: //sky
    begin
      Result.R := 0;
      Result.G := 110/255;
      Result.B := 210/255;
    end;
    12: //cyan
    begin
      Result.R := 0/255;
      Result.G := 215/255;
      Result.B := 215/255;
    end;
    13: //flame
    begin
      Result.R := 210/255;
      Result.G := 70/255;
      Result.B := 0/255;
    end;
    14: //orchid
    begin
      Result.R := 210/255;
      Result.G := 0;
      Result.B := 210/255;
    end;
    15: //harlequin
    begin
      Result.R := 110/255;
      Result.G := 210/255;
      Result.B := 0;
    end;
    16: //lime
    begin
      Result.R := 160/255;
      Result.G := 210/255;
      Result.B := 0;
    end;
    else//blue
    begin
      Result.R := 5/255;
      Result.G := 153/255;
      Result.B := 204/255;
    end;
  end;
end;

procedure TScreenSingView.DrawInfoLyricBar();
var
  SongStart:       real;
  SongEnd:         real;
  SongDuration:    real;
  gapInBeats:      real;

  pos:             real;
  br:              real;

  LineIndex:       integer;
  numLines:        integer;

  x, y, w, h:      real;
  Col:            TRGB;
  CurrentTrack:    integer;
  QuadList:        TQuadList;
  NumQuads, I:     integer;
begin
  if DocumentUI <> nil then Exit;
  x := Theme.Sing.StaticTimeProgress.x;
  y := Theme.Sing.StaticTimeProgress.y;

  w := Theme.Sing.StaticTimeProgress.w;
  h := Theme.Sing.StaticTimeProgress.h;

  //calculate total singing beats of song
  if ScreenSong.Mode = smMedley then
  begin
    SongStart := ScreenSing.MedleyStart * CurrentSong.BPM / 60;
    SongEnd := ScreenSing.MedleyEnd * CurrentSong.BPM / 60;
  end
  else
  begin
    SongStart := CurrentSong.BPM*CurrentSong.Start/60;
    SongEnd := CurrentSong.BPM*TotalTime/60;
  end;
  SongDuration := SongEnd - SongStart;
  gapInBeats := CurrentSong.BPM*CurrentSong.GAP/1000/60;

  // Calculate number of quads to draw
  NumQuads := 1; // progress indicator
  for CurrentTrack := 0 to High(CurrentSong.Tracks) do
    NumQuads := NumQuads + Length(CurrentSong.Tracks[CurrentTrack].Lines);
  SetLength(QuadList, NumQuads);
  I := 0;

  // draw sentence boxes
  for CurrentTrack := 0 to High(CurrentSong.Tracks) do //for P1 of duet or solo lyrics, P2 of duet,..
  begin
    numLines := Length(CurrentSong.Tracks[CurrentTrack].Lines); //Lyric lines
    //set color to player.color
    if (CurrentTrack = 0) then
      Col := GetLyricColor(Ini.SingColor[0])
    else
      Col := GetLyricColor(Ini.SingColor[CurrentTrack]);

    if not Theme.Sing.ProgressVoiceColors then
    begin
      Col.R := Theme.Sing.StaticTimeProgress.ColR;
      Col.G := Theme.Sing.StaticTimeProgress.ColG;
      Col.B := Theme.Sing.StaticTimeProgress.ColB;
    end;
    for LineIndex := 0 to numLines - 1 do
    begin
      if (CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].Notes = nil) then Continue;
      if (ScreenSong.Mode = smMedley) and (CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].Notes[0].StartBeat < CurrentSong.Medley.StartBeat) then Continue;
      pos := (gapInBeats + CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].Notes[0].StartBeat - SongStart) / SongDuration*w;
      br := (CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].Notes[CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].HighNote].StartBeat +
                CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].Notes[CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].HighNote].Duration -
                CurrentSong.Tracks[CurrentTrack].Lines[LineIndex].Notes[0].StartBeat) / SongDuration*w;  //br = last note of sentence position + its duration - first note of sentence position
      QuadList[I].X := x+pos;
      QuadList[I].Y := y;
      QuadList[I].Z := 0;
      QuadList[I].W := br;
      QuadList[I].H := h;
      QuadList[I].Gradient := gdNone;
      QuadList[I].ColR := Col.R;
      QuadList[I].ColG := Col.G;
      QuadList[I].ColB := Col.B;
      QuadList[I].Alpha := 0.6;
      I := I + 1;
    end;
  end;

  // draw progress indicator
  br := Max((gapInBeats + LyricsState.CurrentBeat - SongStart) / SongDuration*w, 0);
  QuadList[I].X := x;
  QuadList[I].Y := y;
  QuadList[I].Z := 0;
  QuadList[I].W := br;
  QuadList[I].H := h;
  QuadList[I].Gradient := gdNone;
  QuadList[I].ColR := Theme.Sing.StaticTimeProgress.ColR;
  QuadList[I].ColG := Theme.Sing.StaticTimeProgress.ColG;
  QuadList[I].ColB := Theme.Sing.StaticTimeProgress.ColB;
  QuadList[I].Alpha := 1;
  Renderer.DrawQuads(QuadList);
end;

end.
