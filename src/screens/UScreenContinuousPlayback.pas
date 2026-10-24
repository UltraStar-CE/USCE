unit UScreenContinuousPlayback;

{$mode delphi}
{$I switches.inc}

interface

uses UCommon, UMenu, UContinuousPlayback, sdl2;

type
  TScreenContinuousDisplay = class(TOptionsMenu)
  protected
    procedure LoadWidgets; override;
  public
    constructor Create; override;
    function ParseInput(Key: cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
  end;

  TScreenContinuousPlayback = class(TOptionsMenu)
  private
    DisplayMenu: TScreenContinuousDisplay;
    RepeatSelection, ResultTime, HighScoreTime: integer;
    PreviousRequested: boolean;
    StageChanged, SkipResults: boolean;
    procedure Advance;
    procedure ChangeStage;
    function CanShowHighScores: boolean;
  protected
    procedure LoadWidgets; override;
  public
    Enabled: integer;
    SongDisplay, SingingDisplay: integer;
    Session: TContinuousPlayback;
    procedure BeginSession;
    function StatusText: UTF8String;
    constructor Create; override;
    destructor Destroy; override;
    procedure OnShow; override;
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
  USongs, USong, UIni, ULyrics, UDisplay;

const
  DisplaySeconds: array[0..4] of integer = (0, 3, 5, 10, 20);

constructor TScreenContinuousDisplay.Create;
begin
  inherited;
  Description := Language.Translate('CONTINUOUS_DISPLAY');
  WhereAmI := Language.Translate('CONTINUOUS_TITLE') + ' > ' + Description;
  Load;
end;

procedure TScreenContinuousDisplay.LoadWidgets;
begin
  AddSelectSlide('CONTINUOUS_SONG_DISPLAY', ScreenContinuousPlayback.SongDisplay,
    [Language.Translate('CONTINUOUS_LYRICS_PROGRESS'), Language.Translate('CONTINUOUS_LYRICS_ONLY'),
     Language.Translate('CONTINUOUS_PROGRESS_ONLY'), Language.Translate('CONTINUOUS_NOTHING')]);
  if PlayersPlay > 0 then
    AddSelectSlide('CONTINUOUS_SINGING_DISPLAY', ScreenContinuousPlayback.SingingDisplay,
      [Language.Translate('CONTINUOUS_FULL'), Language.Translate('CONTINUOUS_NOTES_PLAYER_INFO'),
       Language.Translate('CONTINUOUS_NOTES_ONLY'), Language.Translate('CONTINUOUS_PLAYER_INFO_ONLY'),
       Language.Translate('CONTINUOUS_NOTHING')]);
end;

function TScreenContinuousDisplay.ParseInput(Key: cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean): boolean;
begin
  Result := true;
  if not PressedDown then Exit;
  case Key of
    SDLK_ESCAPE, SDLK_BACKSPACE: FadeTo(@ScreenContinuousPlayback);
    SDLK_RETURN: if Interactions[Interaction].Typ = iButton then FadeTo(@ScreenContinuousPlayback);
    SDLK_UP: InteractPrev;
    SDLK_DOWN: InteractNext;
    SDLK_LEFT: if Interactions[Interaction].Typ = iSelectS then InteractDec;
    SDLK_RIGHT: if Interactions[Interaction].Typ = iSelectS then InteractInc;
    SDLK_TAB: ScreenPopupHelp.ShowPopup;
  end;
end;

constructor TScreenContinuousPlayback.Create;
begin
  inherited;
  Session := TContinuousPlayback.Create;
  Description := Language.Translate('CONTINUOUS_TITLE');
  WhereAmI := Description;
  Load;

end;

destructor TScreenContinuousPlayback.Destroy;
begin
  DisplayMenu.Free;
  Session.Free;
  inherited;
end;

procedure TScreenContinuousPlayback.LoadWidgets;
var Times: array[0..4] of UTF8String; I: integer;
begin
  Times[0] := Language.Translate('CONTINUOUS_SKIP');
  for I := 1 to High(Times) do Times[I] := IntToStr(DisplaySeconds[I]) + ' s';
  AddSelectSlide('CONTINUOUS_TITLE', Enabled,
    [Language.Translate('OPTION_VALUE_OFF'), Language.Translate('OPTION_VALUE_ON')]);
  AddSelectSlide('CONTINUOUS_REPEAT', RepeatSelection,
    [Language.Translate('OPTION_VALUE_OFF'), Language.Translate('OPTION_VALUE_ON')]);
  AddSelectSlide('CONTINUOUS_RESULTS', ResultTime, Times);
  AddSelectSlide('CONTINUOUS_HIGHSCORES', HighScoreTime, Times);
  AddButton('CONTINUOUS_DISPLAY');
end;

function TScreenContinuousPlayback.StatusText: UTF8String;
  function TimeLabel(Index: integer): UTF8String;
  begin
    if DisplaySeconds[Index] = 0 then Result := Language.Translate('CONTINUOUS_SKIP')
    else Result := IntToStr(DisplaySeconds[Index]) + ' s';
  end;
  function OnOff(Value: integer): UTF8String;
  begin
    if Value = 0 then Result := Language.Translate('OPTION_VALUE_OFF')
    else Result := Language.Translate('OPTION_VALUE_ON');
  end;
begin
  Result := Language.Translate('CONTINUOUS_TITLE') + ': ' + OnOff(Enabled);
  if Enabled <> 0 then
    Result := Result + '  |  ' + Language.Translate('CONTINUOUS_REPEAT') + ': ' + OnOff(RepeatSelection) +
      '  |  ' + Language.Translate('CONTINUOUS_RESULTS') + ': ' + TimeLabel(ResultTime) +
      '  |  ' + Language.Translate('CONTINUOUS_HIGHSCORES') + ': ' + TimeLabel(HighScoreTime);
end;

procedure TScreenContinuousPlayback.OnShow;
begin
  inherited;
  Interaction := 0;
  Help.SetHelpID('ID_082');
end;

function TScreenContinuousPlayback.ParseInput(Key: cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean): boolean;
begin
  Result := true;
  if not PressedDown then Exit;
  case Key of
    SDLK_ESCAPE, SDLK_BACKSPACE: FadeTo(@ScreenSong);
    SDLK_RETURN:
      if Interaction = 4 then
      begin
        FreeAndNil(DisplayMenu);
        DisplayMenu := TScreenContinuousDisplay.Create;
        FadeTo(@DisplayMenu);
      end
      else if Interaction = 5 then FadeTo(@ScreenSong);
    SDLK_UP: InteractPrev;
    SDLK_DOWN: InteractNext;
    SDLK_LEFT: if Interactions[Interaction].Typ = iSelectS then InteractDec;
    SDLK_RIGHT: if Interactions[Interaction].Typ = iSelectS then InteractInc;
    SDLK_TAB: ScreenPopupHelp.ShowPopup;
  end;
end;

procedure TScreenContinuousPlayback.BeginSession;
var Selection: TPlaybackSongs; I, SongIndex: integer; Ordered: boolean;
begin
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
  Result := (Length(Player) > 0) and not ScreenSong.RapToFreestyle and
    (not CurrentSong.isDuet or (Ini.DuetScores <> 0));

end;

procedure TScreenContinuousPlayback.ChangeStage;
begin
  StageChanged := false;
  if (Session.Stage = psHighScores) and not CanShowHighScores then Session.NextStage;
  case Session.Stage of
    psResults: FadeTo(@ScreenScore);
    psHighScores: FadeTo(@ScreenHighScores);
    psAdvance: Advance;
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
