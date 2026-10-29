unit UScreenContinuousPlayback;

{$mode delphi}
{$I switches.inc}

interface

uses UCommon, UMenu, UContinuousPlayback, sdl2;

type
  TScreenContinuousPlayback = class(TOptionsMenu)
  private
    SingingSlide, ActiveProfile: integer;
    ResultsOnly: boolean;
    RepeatSelection, ResultTime, HighScoreTime: integer;
    PreviousRequested: boolean;
    StageChanged, SkipResults: boolean;
    procedure SaveProfile;
    procedure LoadProfile;
    procedure SyncProfile;
    procedure Advance;
    procedure ChangeStage;
    procedure ReturnToSong;
    function CanShowHighScores: boolean;
  protected
    procedure LoadWidgets; override;
  public
    Enabled: integer;
    SongDisplay, SingingDisplay: integer;
    Session: TContinuousPlayback;
    procedure BeginSession;
    function BeginNormalResults: boolean;
    constructor Create; override;
    destructor Destroy; override;
    procedure OnShow; override;
    procedure OnHide; override;
    function DrawFG: boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    function ParseInput(Key: cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
    function HandlePlaybackKey(Key: cardinal; PressedDown: boolean; Repeated: boolean = false): boolean;
    procedure SongFinished;
    procedure SongFailed;
    procedure Update;
    procedure Stop;
  end;

implementation

uses SysUtils, UNote, UGraphic, ULanguage, UHelp, ULog, UMusic, UPlaylist,
  USongs, USong, UIni, ULyrics, UDisplay, UCommandLine, ULibraryLockdown;

const
  DisplaySeconds: array[0..8] of integer = (-1, 0, 5, 10, 20, 30, 40, 50, 60);

constructor TScreenContinuousPlayback.Create;
begin
  inherited;
  Session := TContinuousPlayback.Create;
  Enabled := Ini.ContinuousMode;
  ActiveProfile := Enabled;
  LoadProfile;
  if Params.Lockdown then
  begin
    Enabled := 1;
    ActiveProfile := 1;
    LoadProfile;
    if Params.PlaybackResults >= 0 then ResultTime := Params.PlaybackResults;
    if Params.PlaybackHighScores >= 0 then HighScoreTime := Params.PlaybackHighScores;
    if Params.PlaybackSongDisplay >= 0 then SongDisplay := Params.PlaybackSongDisplay;
    if Params.PlaybackSingingDisplay >= 0 then SingingDisplay := Params.PlaybackSingingDisplay;
    RepeatSelection := 1;
  end;
  Description := Language.Translate('SING_CONFIGURATION');
  WhereAmI := Description;
  Load;

end;

destructor TScreenContinuousPlayback.Destroy;
begin
  Session.Free;
  inherited;
end;

procedure TScreenContinuousPlayback.LoadWidgets;
var Times: array[0..High(DisplaySeconds)] of UTF8String; I: integer;
begin
  Times[0] := Language.Translate('PLAYBACK_MANUAL');
  Times[1] := Language.Translate('CONTINUOUS_SKIP');
  for I := 2 to High(Times) do Times[I] := IntToStr(DisplaySeconds[I]) + ' s';
  AddSelectSlide('CONTINUOUS_TITLE', Enabled,
    [Language.Translate('OPTION_VALUE_OFF'), Language.Translate('OPTION_VALUE_ON')]);
  AddSelectSlide('CONTINUOUS_REPEAT', RepeatSelection,
    [Language.Translate('OPTION_VALUE_OFF'), Language.Translate('OPTION_VALUE_ON')]);
  AddSelectSlide('CONTINUOUS_RESULTS', ResultTime, Times);
  AddSelectSlide('CONTINUOUS_HIGHSCORES', HighScoreTime, Times);
  AddSelectSlide('CONTINUOUS_SONG_DISPLAY', SongDisplay,
    [Language.Translate('CONTINUOUS_LYRICS_PROGRESS'), Language.Translate('CONTINUOUS_LYRICS_ONLY'),
     Language.Translate('CONTINUOUS_PROGRESS_ONLY'), Language.Translate('CONTINUOUS_NOTHING')]);
  SingingSlide := AddSelectSlide('CONTINUOUS_SINGING_DISPLAY', SingingDisplay,
    [Language.Translate('CONTINUOUS_FULL'), Language.Translate('CONTINUOUS_NOTES_PLAYER_INFO'),
     Language.Translate('CONTINUOUS_NOTES_ONLY'), Language.Translate('CONTINUOUS_PLAYER_INFO_ONLY'),
     Language.Translate('CONTINUOUS_NOTHING')]);
end;

procedure TScreenContinuousPlayback.SaveProfile;
begin
  with Ini.PlaybackProfiles[ActiveProfile] do
  begin
    RepeatSelection := Self.RepeatSelection;
    ResultTime := Self.ResultTime;
    HighScoreTime := Self.HighScoreTime;
    SongDisplay := Self.SongDisplay;
    SingingDisplay := Self.SingingDisplay;
  end;
end;

procedure TScreenContinuousPlayback.LoadProfile;
begin
  with Ini.PlaybackProfiles[ActiveProfile] do
  begin
    Self.RepeatSelection := RepeatSelection;
    Self.ResultTime := ResultTime;
    Self.HighScoreTime := HighScoreTime;
    Self.SongDisplay := SongDisplay;
    Self.SingingDisplay := SingingDisplay;
  end;
  if Length(SelectsS) >= 6 then
  begin
    SelectsS[1].SelectedOption := RepeatSelection;
    SelectsS[2].SelectedOption := ResultTime;
    SelectsS[3].SelectedOption := HighScoreTime;
    SelectsS[4].SelectedOption := SongDisplay;
    SelectsS[5].SelectedOption := SingingDisplay;
  end;
end;

procedure TScreenContinuousPlayback.SyncProfile;
begin
  if Params.Lockdown and LibraryLockdown.Active then
  begin
    Enabled := 1;
    RepeatSelection := 1;
    if Length(SelectsS) >= 2 then
    begin
      SelectsS[0].SelectedOption := Enabled;
      SelectsS[1].SelectedOption := RepeatSelection;
    end;
  end;
  Ini.ContinuousMode := Enabled;
  if ActiveProfile = Enabled then Exit;
  SaveProfile;
  ActiveProfile := Enabled;
  LoadProfile;
end;

procedure TScreenContinuousPlayback.OnHide;
begin
  SyncProfile;
  SaveProfile;
  Ini.ContinuousMode := Enabled;
  Ini.Save;
  inherited;
end;

function TScreenContinuousPlayback.DrawFG: boolean;
begin
  SyncProfile;
  Result := inherited;
end;

function TScreenContinuousPlayback.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
begin
  Result := inherited ParseMouse(MouseButton, BtnDown, X, Y);
  SyncProfile;
end;

procedure TScreenContinuousPlayback.OnShow;
begin
  inherited;
  SyncProfile;
  SelectsS[0].SelectedOption := Enabled;
  SelectsS[SingingSlide].Visible := not ScreenName.LyricsOnly;
  Interaction := 0;
  Help.SetHelpID('ID_082');
end;

procedure TScreenContinuousPlayback.ReturnToSong;
begin
  // The destination OnShow runs before this screen OnHide during a fade.
  ScreenSong.PreservePreviewForReturn;
  FadeTo(@ScreenSong);
end;

function TScreenContinuousPlayback.ParseInput(Key: cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean): boolean;
begin
  Result := true;
  if not PressedDown then Exit;
  case Key of
    SDLK_ESCAPE, SDLK_BACKSPACE: ReturnToSong;
    SDLK_RETURN: if Interactions[Interaction].Typ = iButton then ReturnToSong;
    SDLK_UP: InteractPrev;
    SDLK_DOWN: InteractNext;
    SDLK_LEFT: if Interactions[Interaction].Typ = iSelectS then InteractDec;
    SDLK_RIGHT: if Interactions[Interaction].Typ = iSelectS then InteractInc;
    SDLK_TAB: ScreenPopupHelp.ShowPopup;
  end;
  SyncProfile;
end;

procedure TScreenContinuousPlayback.BeginSession;
var Selection: TPlaybackSongs; I, SongIndex: integer; Ordered: boolean;
begin
  ResultsOnly := false;
  SyncProfile;
  Ordered := (CatSongs.CatNumShow = -3) and (PlaylistMan.CurPlaylist >= 0) and
    (PlaylistMan.CurPlaylist < Length(PlaylistMan.Playlists)) and
    PlaylistMan.Playlists[PlaylistMan.CurPlaylist].FixedOrder;
  Selection := nil;
  if Ordered then
  begin
    for I := 0 to High(PlaylistMan.Playlists[PlaylistMan.CurPlaylist].Items) do
    begin
      SongIndex := PlaylistMan.Playlists[PlaylistMan.CurPlaylist].Items[I].SongID;
      if (SongIndex >= 0) and (SongIndex < Length(CatSongs.Song)) and
        CatSongs.Song[SongIndex].Visible and not CatSongs.Song[SongIndex].Main then
      begin
        SetLength(Selection, Length(Selection) + 1);
        Selection[High(Selection)] := SongIndex;
      end;
    end;
  end
  else
    for I := 0 to High(CatSongs.Song) do
      if CatSongs.Song[I].Visible and not CatSongs.Song[I].Main then
      begin
        SetLength(Selection, Length(Selection) + 1);
        Selection[High(Selection)] := I;
      end;
  if Length(Selection) = 0 then Exit;
  Session.ResultSeconds := DisplaySeconds[ResultTime];
  Session.HighScoreSeconds := DisplaySeconds[HighScoreTime];
  Session.Start(Selection, ScreenSong.Interaction, Ordered,
    RepeatSelection = 1, PlayersPlay > 0);
  ScreenSong.Mode := smNormal;
  Advance;
end;

function TScreenContinuousPlayback.BeginNormalResults: boolean;
begin
  SyncProfile;
  // Keep the existing manual score/highscore flow for the default profile.
  Result := (ResultTime <> 0) or (HighScoreTime <> 0);
  if not Result then Exit;
  ResultsOnly := true;
  Session.Stop;
  Session.Scored := PlayersPlay > 0;
  Session.ResultSeconds := DisplaySeconds[ResultTime];
  Session.HighScoreSeconds := DisplaySeconds[HighScoreTime];
  Session.FinishSong(true);
  ChangeStage;
end;

procedure TScreenContinuousPlayback.Advance;
var SongIndex, Skipped: integer; RestartSing: boolean; Message: UTF8String;
begin
  if PreviousRequested then
  begin
    PreviousRequested := false;
    Session.PreviousSong(SongIndex);
  end
  else if not Session.NextSong(SongIndex) then
  begin
    Skipped := Session.Skipped;
    Stop;
    Message := Language.Translate('CONTINUOUS_FINISHED');
    if Skipped > 0 then Message := Message + ' ' +
      Format(Language.Translate('CONTINUOUS_SKIPPED'), [Skipped]);
    ScreenPopupInfo.ShowPopup(Message);
    Exit;
  end;
  CatSongs.Selected := SongIndex;
  ScreenSong.Interaction := SongIndex;
  SkipResults := false;
  RestartSing := Display.CurrentScreen = @ScreenSing;
  if RestartSing then
  begin
    // Restart through the existing lifecycle only after both viewports finish
    // drawing, so no frame retains references to the previous song's lyrics.
    AudioPlayback.Stop;
    ScreenSing.OnHide;
    ScreenSing.OnShow;
    ScreenSing.OnShowFinish;
  end
  else FadeTo(@ScreenSing);
end;

procedure TScreenContinuousPlayback.Stop;
begin
  if not Session.Active then Exit;
  Session.Stop;
  PreviousRequested := false;
  if PlayersPlay > 0 then AudioInput.CaptureStop;
  AudioPlayback.SetSyncSource(nil);
  AudioPlayback.Stop;
  LyricsState.Stop;
  LyricsState.SetSyncSource(nil);
  StageChanged := false;
  ScreenSing.FadeOut := true;
  FadeTo(@ScreenSong);
end;

function TScreenContinuousPlayback.CanShowHighScores: boolean;
begin
  Result := (Length(Player) > 0) and
    (not CurrentSong.isDuet or (Ini.DuetScores <> 0));

end;

procedure TScreenContinuousPlayback.ChangeStage;
begin
  StageChanged := false;
  if (Session.Stage = psHighScores) and not CanShowHighScores then Session.NextStage;
  case Session.Stage of
    psResults: FadeTo(@ScreenScore);
    psHighScores: FadeTo(@ScreenHighScores);
    psAdvance: if ResultsOnly then Stop else Advance;
  end;
end;

procedure TScreenContinuousPlayback.SongFinished;
begin
  Session.FinishSong(not SkipResults);
  StageChanged := true;
end;

procedure TScreenContinuousPlayback.SongFailed;
begin
  Log.LogError('Skipping unreadable song: ' + CurrentSong.Artist + ' - ' + CurrentSong.Title + ' (' + CurrentSong.LastError + ')',
    'Continuous playback');
  Session.RejectCurrentSong;
  StageChanged := true;
end;

function TScreenContinuousPlayback.HandlePlaybackKey(Key: cardinal; PressedDown: boolean; Repeated: boolean): boolean;
begin
  Result := Session.Active and PressedDown;
  if not Result then Exit;
  if ResultsOnly and not (Key in [SDLK_ESCAPE, SDLK_BACKSPACE, SDLK_RETURN]) then Exit(false);
  if (Key = SDLK_RETURN) and (Display.CurrentScreen = @ScreenScore) and
     (ScreenScore.Interaction <> -1) then Exit(false);
  if ((Key = SDLK_LEFT) or (Key = SDLK_RIGHT)) and
     ((SDL_GetModState and (KMOD_CTRL or KMOD_ALT or KMOD_SHIFT)) <> 0) then
    Exit(false);
  if Repeated and ((Key in [SDLK_ESCAPE, SDLK_BACKSPACE, SDLK_SPACE, SDLK_P, SDLK_RETURN]) or
    (Key = SDLK_LEFT) or (Key = SDLK_RIGHT)) then Exit;
  case Key of
    SDLK_ESCAPE, SDLK_BACKSPACE: Stop;
    SDLK_SPACE, SDLK_P:
      if Display.CurrentScreen = @ScreenSing then ScreenSing.Pause
      else
      begin
        Session.Paused := not Session.Paused;
        if Session.Paused then AudioPlayback.Pause else AudioPlayback.Play;
      end;
    SDLK_LEFT, SDLK_RIGHT:
    begin
      PreviousRequested := Key = SDLK_LEFT;
      if Session.Stage = psSong then
      begin
        SkipResults := true;
        ScreenSing.Finish;
      end
      else begin Session.Stage := psAdvance; StageChanged := true; end;
    end;
    SDLK_RETURN:
      if Session.Stage in [psResults, psHighScores] then
      begin
        Session.NextStage;
        StageChanged := true;
      end
      else Result := false;
    else Result := false;
  end;
end;

procedure TScreenContinuousPlayback.Update;
var Suspended: boolean;
begin
  if not Session.Active then Exit;
  if ScreenAct <> Screens then Exit;
  Suspended := (Display.NextScreen <> nil) or ScreenPopupHelp.Visible or
    ScreenPopupError.Visible or ScreenPopupInfo.Visible or ScreenPopupCheck.Visible or
    ScreenPopupSendScore.Visible or not Display.CurrentScreen^.ShowFinish;
  if Session.Tick(SDL_GetTicks, Suspended) then StageChanged := true;
  if StageChanged and not Suspended then ChangeStage;
end;

end.
