unit UScreenContinuousPlayback;

{$mode delphi}
{$I switches.inc}

interface

uses UCommon, UMenu, UMenuText, UContinuousPlayback, sdl2;

type
  TScreenContinuousPlayback = class(TOptionsMenu)
  private
    RepeatSelection, ResultTime, HighScoreTime: integer;
    Hint: TText;
    StageChanged, SkipResults: boolean;
    procedure Advance;
    procedure ChangeStage;
    function CanShowHighScores: boolean;
  protected
    procedure LoadWidgets; override;
  public
    Enabled: integer;
    Session: TContinuousPlayback;
    procedure BeginSession;
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
  USongs, USong, UIni, UParty, ULyrics, URenderer, UDisplay;

const
  DisplaySeconds: array[0..4] of integer = (0, 3, 5, 10, 20);

constructor TScreenContinuousPlayback.Create;
begin
  inherited;
  Session := TContinuousPlayback.Create;
  Description := Language.Translate('CONTINUOUS_TITLE');
  WhereAmI := Description;
  Load;
  Hint := TText.Create(20, 4, '');
  Hint.W := 760;
  Hint.H := 22;
  Hint.Size := 14;
  Hint.ColR := 1; Hint.ColG := 1; Hint.ColB := 1;
end;

destructor TScreenContinuousPlayback.Destroy;
begin
  Hint.Free;
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
      if Interaction = 4 then FadeTo(@ScreenSong);
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
  if not Session.NextSong(SongIndex) then
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
  if Repeated and (Key in [SDLK_ESCAPE, SDLK_BACKSPACE, SDLK_SPACE, SDLK_P, SDLK_N, SDLK_RETURN]) then Exit;
  case Key of
    SDLK_ESCAPE, SDLK_BACKSPACE: Stop;
    SDLK_SPACE, SDLK_P:
      if Display.CurrentScreen = @ScreenSing then ScreenSing.Pause
      else
      begin
        Session.Paused := not Session.Paused;
        if Session.Paused then AudioPlayback.Pause else AudioPlayback.Play;
      end;
    SDLK_N:
      if Session.Stage = psSong then
      begin
        SkipResults := true;
        ScreenSing.Finish;
      end
      else begin Session.Stage := psAdvance; StageChanged := true; end;
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
var Suspended: boolean; LabelText: UTF8String;
begin
  if not Session.Active then Exit;
  LabelText := Language.Translate('CONTINUOUS_CONTROLS');
  if Session.Paused then LabelText := Language.Translate('CONTINUOUS_PAUSED') + ' | ' + LabelText;
  if Session.Skipped > 0 then LabelText := LabelText + ' | ' +
    Format(Language.Translate('CONTINUOUS_SKIPPED'), [Session.Skipped]);
  Hint.Y := 4;
  if (Session.Stage = psSong) and not Session.Scored and CurrentSong.isDuet then
    Hint.Y := 95;
  Renderer.DrawQuad(0, Hint.Y - 4, 0, 800, 26, 0, 0, 0, 0.6);
  Hint.Text := LabelText;
  Hint.Draw;
  if ScreenAct <> Screens then Exit;
  Suspended := (Display.NextScreen <> nil) or ScreenPopupHelp.Visible or
    ScreenPopupError.Visible or ScreenPopupInfo.Visible or ScreenPopupCheck.Visible or
    ScreenPopupSendScore.Visible or not Display.CurrentScreen^.ShowFinish;
  if Session.Tick(SDL_GetTicks, Suspended) then StageChanged := true;
  if StageChanged and not Suspended then ChangeStage;
end;

end.
