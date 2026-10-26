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
 *}



unit UScreenSingController;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UVoiceParts,
  UPlayerLayout,
  UVoiceAssignments,
  UAvatars,
  UCommon,
  UFiles,
  UGraphicClasses,
  UHookableEvent,
  UIni,
  ULyrics,
  UMenu,
  UMusic,
  UPath,
  URenderer,
  UScreenSingView,
  USingScores,
  USkins,
  USongs,
  UThemes,
  UTime,
  sdl2,
  SysUtils,
  UText;

type
  TLyricsSyncSource = class(TSyncSource)
    function GetClock(): real; override;
  end;

  TMusicSyncSource = class(TSyncSource)
    function GetClock(): real; override;
  end;

  TTimebarMode = (
    tbmCurrent,   // current song position
    tbmRemaining, // remaining time
    tbmTotal      // total time
  );

type
  TScreenSingController = class(TMenu)
  private
    StartNote, EndNote:     TPos;
    fCountIn: boolean;
    PlaybackSeeked: boolean;
    fStartTime, fFirstNote: real;

    procedure SeekTo(Position: real; ResetScoring: boolean = true);
    procedure LoadNextSong();
    procedure SongError();
    procedure ResetLinesAndLyrics();
    procedure ClearLyricEngines();
    procedure CalculateStartTime;
    procedure SaveLocalScores;
    procedure AnnounceRemoteSongStarted;
    procedure AnnounceRemoteSongPaused;
    procedure AnnounceRemoteSongResumed;
    procedure AnnounceRemoteSongEnded;
    procedure AnnounceRemoteSongPosition(const Reason: UTF8String);
    procedure SendRemoteLyrics;
    procedure SendRemoteScoreSheet;
    procedure SendRemoteScoreSnapshot(Force: boolean);
    function RemoteMediaStartUs: int64;
    function RemoteSongDurationUs: int64;
    procedure ResumeAfterScoringTail;
  public
    ScoringTailActive: boolean;
    ScoringTailEndBeat: integer;
    CheckPlayerConfigOnNextSong: boolean;
    eSongLoaded: THookableEvent; //< event is called after lyrics of a song are loaded on OnShow
    Paused:     boolean; //pause Mod
    NumEmptySentences: array of integer;
    // views
    fShowVisualization: boolean;
    fShowBackground: boolean;

    fCurrentVideo: IVideo;
    fVideoClip:    IVideo;
    fLyricsSync: TLyricsSyncSource;
    fMusicSync: TMusicSyncSource;
    fTimebarMode: TTimebarMode;

    PlayMidi: boolean;

    removeVoice: boolean;
    fShowWebcam: boolean;

    // TODO: delete this?
    Act_MD5Song: string;

    MedleyStart, MedleyEnd: real;

    Lyrics: TLyricEngine;
    VoiceLyrics: array of TLyricEngine;
    DisplayedVoices: array of integer;
    DisplayedVoiceBanks: array of integer;
    VoiceBankCounts: array[0..1] of integer;

    // score manager:
    Scores: TSingScores;

    //the song was sung to the end
    SungToEnd: boolean;

    // some settings to be set by plugins
    Settings: record
      Finish: Boolean; //< if true, screen will finish on next draw

      OscilloscopeVisible: Boolean; //< shows or hides oscilloscope
      LyricsVisible:       Boolean; //< shows or hides lyrics
      NotesVisible:        array [0..IMaxPlayerCount-1] of Boolean; //< if NotesVisible[playerIndex] is set the notes for the specified player are visible. By default all players notes are visible
      FeedbackVisible:     Boolean; //< rating popups and singing effects
      ScoresVisible:       Boolean; //< shows or hides scores
      AvatarsVisible:      Boolean; //< shows or hides avatars
      TimeBarVisible:      Boolean; //< shows or hides timebar
      InputVisible:        Boolean; //< shows or hides input (sung notes)

      PlayerEnabled:  Integer; //< defines whether a player can score atm

      SoundEnabled:   Boolean; //< mute or unmute sound
    end;

    // MIDI
    ChannelOff  : integer;

    MidiFadeIn: boolean;
    MidiFadeOut: boolean;
    FadeTime: cardinal;

    InfoMessageBG: cardinal;
    InfoMessageText: cardinal;

    MessageTime: cardinal;
    MessageTimeFade: cardinal;

    TextMedleyFadeOut: boolean;
    TextMedleyFadeTime: cardinal;

    // names
    PlayerNames: array [1..IMaxPlayerCount] of UTF8String;
    PlayerDuetNames:array [1..IMaxPlayerCount] of UTF8String;

    Tex_Background: TTexture;
    Tex_BackgroundAspectRatio: single;
    // controls both background image and video
    BackgroundAspectCorrection: TAspectCorrection;
    PictureAspectCorrection: TAspectCorrection;
    FadeOut: boolean;

    procedure ClearSettings;
    procedure AllNotesVisible(visible: boolean);
    procedure ApplySettings; //< applies changes of settings record
    procedure EndSong;

    procedure RefreshInputRoster(NewCount: integer);
    constructor Create; override;
    destructor Destroy; override;
    procedure OnShow; override;
    procedure OnShowFinish; override;
    procedure OnHide; override;
    function Draw: boolean; override;

    function ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;

    function ParseMouse(MouseButton: integer; BtnDown: boolean; MouseX, MouseY: integer): boolean; override;

    function FinishedMusic: boolean;
    function ContinueDelayedScoring: boolean;

    procedure AutoSendScore;
    procedure AutoSaveScore;

    procedure Finish; virtual;
    procedure Pause; // toggle pause
    procedure UpdateMedleyStats(medley_end: boolean);
    procedure OnSentenceEnd(Track: integer; SentenceIndex: cardinal; OnlyPlayer: integer = -1);     // for linebonus + singbar
    procedure ClearVoiceLyrics;
    procedure ConfigureVoiceLyrics;
    procedure LayoutVoiceLyrics;
    procedure PositionVoiceLyrics(DisplayIndex: integer);
    procedure OnSentenceChange(Track: integer; SentenceIndex: cardinal);  // for golden notes
    property CountIn: boolean read fCountIn write fCountIn;
    property FirstNote: real read fFirstNote;
  end;

var screenSingViewRef: TScreenSingView;
    TotalTime:              real;

const
  ID='ID_022';   //for help system

implementation

uses
  UCommandLine,
  UContinuousPlayback,
  UDatabase,
  UDisplay,
  UDLLManager,
  UDraw,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UNote,
  URecord,
  URemoteBridgeIPC,
  URemoteInput,
  UInputSource,
  UParty,
  UPathUtils,
  USong,
  UUnicodeUtils,
  UWebcam,
  UWebSDK,
  Classes,
  Math;

const
  MAX_MESSAGE = 3;
  MINIMUM_START_TIME = 3;

var
  RemoteSongSeq: integer = 0;
  LastRemoteScoreSnapshotTick: cardinal = 0;

const
  REMOTE_SCORE_SNAPSHOT_MS = 500;

// method for input parsing. if false is returned, getnextwindow
// should be checked to know the next window to load;

function TScreenSingController.ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean = false): boolean;
var
  SDL_ModState: word;
  ResumeAfterHelp: boolean;
  VoiceIndex: integer;
  IntroPosition: real;
begin
  Result := true;
  if ScreenContinuousPlayback.HandlePlaybackKey(PressedKey, PressedDown, Repeated) then Exit;
  if (PressedDown) then
  begin // key down

    SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
    + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT);

    // check normal keys
    case PressedKey of
      SDLK_Q:
      begin
        // when not ask before exit then finish now
        if (Ini.AskbeforeDel <> 1) then
          Finish
        // else just pause and let the popup make the work
        else if not Paused then
          Pause;

        Result := false;
        Exit;
      end;

      // restart song
      SDLK_R:
      begin
        if ScreenSong.Mode = smMedley then Exit;
        SeekTo(fStartTime);
        PlaybackSeeked := false;
        AnnounceRemoteSongStarted;

        Exit;
      end;

      // show visualization
      SDLK_V:
      begin
        if fShowWebcam then
        begin
          Webcam.Release;
          fShowWebCam:=false;
        end;
        if ((fShowBackground = true) and (Ini.VideoEnabled = 1) and CurrentSong.Video.IsSet())
                             or (fShowVisualization and not CurrentSong.Background.IsSet()) then //switch to video
        begin
          Log.LogStatus('decided to switch to video', 'UScreenSing.ParseInput');
          fShowBackground := false;
          fCurrentVideo := nil;
          fShowVisualization := false;
          fCurrentVideo := fVideoClip;
          if (Assigned(fCurrentVideo)) then
          begin
            fCurrentVideo.SetAspectCorrection(BackgroundAspectCorrection);
            fCurrentVideo.Position := CurrentSong.VideoGAP + AudioPlayback.Position;
          end;
          Log.LogStatus('finished switching to video', 'UScreenSing.ParseInput');
        end
        else
        begin
          if fShowVisualization and CurrentSong.Background.IsSet() then
          begin //switch to Background only
            Log.LogStatus('decided to switch to background', 'UScreenSing.ParseInput');
            fShowBackground := true;
            fCurrentVideo := nil;
            fShowVisualization := false;
            Log.LogStatus('finished switching to background', 'UScreenSing.ParseInput');
          end
          else
          begin //Video is currently visible, change to visualization
            Log.LogStatus('decided to switch to visualization', 'UScreenSing.ParseInput');
            fShowVisualization := true;
            fCurrentVideo := Visualization.Open(PATH_NONE);
            fCurrentVideo.play;
            Log.LogStatus('finished switching to visualization', 'UScreenSing.ParseInput');
          end;
        end;
        Exit;
      end;

      // show Webcam
      SDLK_W:
      begin
        if (fShowWebCam = false) then
        begin
          fCurrentVideo := nil;
          fShowVisualization := false;
          fShowBackground := false;
          Webcam.Restart;
          if (Webcam.Capture = nil) then
          begin
            fShowWebCam := false;
            fShowBackground := true;
            ScreenPopupError.ShowPopup(Language.Translate('SING_OPTIONS_WEBCAM_NO_WEBCAM'))
          end
          else
            fShowWebCam := true;
        //  ChangeEffectLastTick := SDL_GetTicks;
        //  SelectsS[WebcamParamsSlide].Visible := true;
        //  LastTickFrame := SDL_GetTicks;
        end
        else
        begin
          Webcam.Release;
          fShowWebCam:=false;
        end;

        Exit;
      end;

      // pause
      SDLK_P:
      begin
        Pause;
        Exit;
      end;

      // toggle time display: running time/remaining time/total time / SHIFT: show/hide time bar
      SDLK_T:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          ScreenSing.Settings.TimeBarVisible := not ScreenSing.Settings.TimeBarVisible;
          Exit;
        end
        else
        begin
          if (fTimebarMode = High(TTimebarMode)) then
            fTimebarMode := Low(TTimebarMode)
          else
            Inc(fTimebarMode);

          Ini.SingTimebarMode := Ord(fTimebarMode);
          Ini.SaveSingTimebarMode;
          Exit;
        end;
      end;

      // skip intro / SHIFT: show/hide score display
      SDLK_S:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          ScreenSing.Settings.ScoresVisible := not ScreenSing.Settings.ScoresVisible;
          Exit;
        end
        else
        begin
          if (not CurrentSong.isDuet and (GetTimeFromBeat(Lyrics.GetUpperLine().StartNote) - AudioPlayback.Position > 6)) then
          begin
            SeekTo(GetTimeFromBeat(Lyrics.GetUpperLine().StartNote) - 5, false);
          end
          else if CurrentSong.isDuet then
          begin
            IntroPosition := 1.0E20;
            for VoiceIndex := 0 to High(VoiceLyrics) do
              if VoiceLyrics[VoiceIndex].GetUpperLine <> nil then
                IntroPosition := Min(IntroPosition,
                  GetTimeFromBeat(VoiceLyrics[VoiceIndex].GetUpperLine.StartNote));
            if (IntroPosition < 1.0E20) and (IntroPosition - AudioPlayback.Position > 6) then
              SeekTo(IntroPosition - 5, false);
          end;
          Exit;
        end;
      end;

      // SHIFT: show/hide oscilloscope
      SDLK_O:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          ScreenSing.Settings.OscilloscopeVisible := not ScreenSing.Settings.OscilloscopeVisible;
          Exit;
        end;
      end;

      // SHIFT: show/hide notes
      SDLK_N:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          if (ScreenSing.Settings.NotesVisible[0]) then begin
            // if first player is currently visible, set all players to not visible
            AllNotesVisible(false);
          end else begin
            // else set all players to visible
            AllNotesVisible(true);
          end;
          Exit;
        end;
      end;

      // SHIFT: show/hide notes
      SDLK_L:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          ScreenSing.Settings.LyricsVisible := not ScreenSing.Settings.LyricsVisible;
          Exit;
        end;
      end;

      // SHIFT: show/hide avatars and player names
      SDLK_A:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          ScreenSing.Settings.AvatarsVisible := not ScreenSing.Settings.AvatarsVisible;
          Exit;
        end
        else
        begin
          if fShowBackground then
            PictureAspectCorrection := TAspectCorrection((Ord(PictureAspectCorrection)+1) mod (Ord(High(TAspectCorrection))+1))
          else
          begin
            BackgroundAspectCorrection := TAspectCorrection((Ord(BackgroundAspectCorrection)+1) mod (Ord(High(TAspectCorrection))+1));
            if Assigned(fCurrentVideo) then
              fCurrentVideo.SetAspectCorrection(BackgroundAspectCorrection);
          end;
        end;
      end;

      // SHIFT: show/hide microphone input/sung notes
      SDLK_I:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          ScreenSing.Settings.InputVisible := not ScreenSing.Settings.InputVisible;
          Exit;
        end;
      end;

      // SHIFT: show/hide (toggle) all display elements
      SDLK_H:
      begin
        if (SDL_ModState = KMOD_LSHIFT) then
        begin
          if (ScreenSong.Mode <> smNormal) and (ScreenSong.Mode <> smMedley) then
            Exit;

          if (ScreenSing.Settings.NotesVisible[0]) then begin
            // if first player is currently visible, set all players to not visible
            AllNotesVisible(false);
          end else begin
            // else set all players to visible
            AllNotesVisible(true);
          end;
          // synchronize show/hide of all other elements with NotesVisible
          ScreenSing.Settings.LyricsVisible       := (ScreenSing.Settings.NotesVisible[0]);
          ScreenSing.Settings.ScoresVisible       := (ScreenSing.Settings.NotesVisible[0]);
          ScreenSing.Settings.AvatarsVisible      := (ScreenSing.Settings.NotesVisible[0]);
          ScreenSing.Settings.TimeBarVisible      := (ScreenSing.Settings.NotesVisible[0]);
          ScreenSing.Settings.InputVisible        := (ScreenSing.Settings.NotesVisible[0]);
          ScreenSing.Settings.OscilloscopeVisible := (ScreenSing.Settings.NotesVisible[0]);
          Exit;
        end;
      end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE:
      begin
        // record sound hack:
        //Sound[0].BufferLong
        if ScreenSong.Mode = smMedley then
          PlaylistMedley.NumMedleySongs := PlaylistMedley.CurrentMedleySong;

        Finish;
        FadeOut := true;
        AudioPlayback.PlaySound(SoundLib.Back);
      end;

      SDLK_SPACE:
      begin
        Pause;
      end;

      SDLK_K:
      begin
        AudioPlayback.ToggleKaraoke;
      end;

      SDLK_RIGHT:
      begin
        if ((SDL_ModState and KMOD_LCTRL) <> 0) then
          SeekTo(Min(AudioPlayback.Position + 5.0, LyricsState.TotalTime));

      end;

      SDLK_LEFT:
      begin
        if (SDL_ModState = KMOD_LCTRL) and (AudioPlayback.Position >= 20.0) then
          SeekTo(AudioPlayback.Position - 5.0);

      end;

      SDLK_TAB:
      begin
        if (SDL_ModState = KMOD_LCTRL) then // change visualization preset
        begin
          if fShowVisualization then
            fCurrentVideo.Position := now; // move to a random position

          if (fShowWebcam) then
          begin
            if (Ini.WebCamEffect < 10) then
              Ini.WebCamEffect := Ini.WebCamEffect + 1
            else
              Ini.WebCamEffect := 0;
          end;
        end
        else // show help popup
        begin
          ResumeAfterHelp := not Paused;
          if ResumeAfterHelp then
            Pause;
          ScreenPopupHelp.ShowPopup(ResumeAfterHelp);
        end;
      end;
    end;
  end;
end;

function TScreenSingController.ParseMouse(MouseButton: integer; BtnDown: boolean;
  MouseX, MouseY: integer): boolean;
var LocalX, LocalY, StartTime, EndTime: real;
begin
  if (MouseButton = SDL_BUTTON_LEFT) and BtnDown and ShowFinish and
     not FadeOut and Settings.TimeBarVisible and (ScreenWPerScreen > 0) then
  begin
    LocalX := (MouseX mod ScreenWPerScreen) * RenderW / ScreenWPerScreen;
    LocalY := MouseY * RenderH / ScreenH;
    with Theme.Sing.StaticTimeProgress do
      if (W > 0) and (LocalX >= X) and (LocalX <= X + W) and
         (LocalY >= Y - 4) and (LocalY <= Y + H + 4) then
      begin
        StartTime := CurrentSong.Start;
        EndTime := LyricsState.TotalTime;
        if ScreenSong.Mode = smMedley then StartTime := MedleyStart;
        if EndTime > StartTime then
          SeekTo(StartTime + (EndTime - StartTime) * (LocalX - X) / W);
        Exit(true);
      end;
  end;
  Result := inherited ParseMouse(MouseButton, BtnDown, MouseX, MouseY);
end;

procedure TScreenSingController.SeekTo(Position: real; ResetScoring: boolean);
var I: integer; Color: TRGB;
begin
  if ResetScoring then
  begin
    PlaybackSeeked := true;
    for I := 0 to High(Player) do
    begin
      Player[I].ResetScores;
      Player[I].ScoreLast := 0;
      Player[I].LastSentencePerfect := false;
    end;
    Scores.KillAllPopUps;
    Scores.ClearPlayers;
    Color.R := 0; Color.G := 0; Color.B := 0;
    for I := 0 to PlayersPlay - 1 do Scores.AddPlayer(Tex_ScoreBG[I], Color);
    Scores.Init;
    GoldenRec.KillAll;
  end;
  StopSingClicks;
  AudioPlayback.SetPosition(Position);
  LyricsState.SetCurrentTime(Position);
  ResumeAfterScoringTail;
  LyricsState.UpdateBeats;
  ClearLyricEngines;
  ResetLinesAndLyrics;
  fCountIn := Position < CurrentSong.Start;
  if Assigned(fCurrentVideo) then
    fCurrentVideo.Position := CurrentSong.VideoGAP + Position;
end;

procedure TScreenSingController.RefreshInputRoster(NewCount: integer);
var I, OldCount: integer; Color: TRGB; Levels: array[0..UIni.IMaxPlayerCount-1] of integer;
begin
  if (ScreenSong.Mode <> smNormal) or Party.bPartyGame or FadeOut or
    ScoringTailActive or not ShowFinish then Exit;
  NewCount := EnsureRange(NewCount,0,UIni.IMaxPlayerCount);
  OldCount := PlayersPlay;
  if NewCount = OldCount then Exit;
  for I := 0 to High(Player) do Levels[I] := Player[I].Level;
  ScreenName.LoadPlayersFromIni(true);
  for I := 0 to Min(OldCount,NewCount)-1 do Player[I].Level := Levels[I];
  for I := OldCount to NewCount-1 do
  begin
    Player[I].ResetScores;
    Player[I].Track := VoiceAssignments.VoiceForPlayer(I,CurrentSong.VoiceCount);
    Player[I].InputSource := Ord(PlayerInputSource(I));
  end;
  Scores.KillAllPopUps;
  Scores.ClearPlayers;
  Color.R:=0; Color.G:=0; Color.B:=0;
  for I:=0 to NewCount-1 do Scores.AddPlayer(Tex_ScoreBG[I],Color,Player[I].ScoreTotalInt);
  Scores.Init;
  if (OldCount=0) and (NewCount>0) then AudioInput.CaptureStart;
  if NewCount=0 then AudioInput.CaptureStop;
  if ScreenContinuousPlayback.Session.Active then ScreenContinuousPlayback.Session.Scored:=NewCount>0;
  SendRemoteScoreSnapshot(true);
  RemoteBridgeIPC.SendGameState('singing',RemoteSongSeq,0);
  Log.LogStatus(Format('players %d -> %d',[OldCount,NewCount]),'Input roster');
end;

procedure TScreenSingController.Pause;
begin
  if (not Paused) then  // enable pause
  begin
    // pause time
    Paused := true;

    LyricsState.Pause();
    StopSingClicks;

    // pause music
      AudioPlayback.Pause;

    // pause video
    if (fCurrentVideo <> nil) then
      fCurrentVideo.Pause;

    AnnounceRemoteSongPaused;
  end
  else              // disable pause
  begin
    LyricsState.Start();

    // play music
      if not ScoringTailActive or not AudioPlayback.Finished then
        AudioPlayback.Play;

    // video
    if (fCurrentVideo <> nil) then
      fCurrentVideo.Pause;

    Paused := false;
    AnnounceRemoteSongResumed;
  end;
  if ScreenContinuousPlayback.Session.Active then
    ScreenContinuousPlayback.Session.Paused := Paused;
end;

constructor TScreenSingController.Create;
begin
  inherited Create;
  ScreenSing := self;
  screenSingViewRef := TScreenSingView.Create();
  CheckPlayerConfigOnNextSong := true;
  // Preserve video framing; still images fill the stage without distortion.
  BackgroundAspectCorrection := acoLetterBox;
  PictureAspectCorrection := acoCrop;

  ClearSettings;
end;

destructor TScreenSingController.Destroy;
begin
  FreeAndNil(screenSingViewRef);
  Lyrics.Free;
  ClearVoiceLyrics;
  fLyricsSync.Free;
  fMusicSync.Free;
  eSongLoaded.Free;
  Scores.Free;
  Tex_Background.Free;
  inherited;
end;

procedure TScreenSingController.OnShow;
var
  BadPlayer, I: integer;
  Col: TRGB;

begin
  inherited;

  ScoringTailActive := false;
  RemoteBridgeIPC.ApplyPendingPlayerCount(true);
  Log.LogStatus('Begin', 'OnShow');

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenSingController');

  FadeOut := false;

  screenSingViewRef.CloseMessage();

  //the song was sung to the end
  SungToEnd := false;
  PlaybackSeeked := false;

  ClearSettings;
  Party.CallBeforeSing;

  // prepare players
  SetLength(Player, PlayersPlay);

  //Reset Player Medley stats
  if (ScreenSong.Mode = smMedley) then
  begin
    PlaylistMedley.CurrentMedleySong:=1;

    PlaylistMedley.NumPlayer := PlayersPlay;
    SetLength(PlaylistMedley.Stats, 0);
  end;

  fTimebarMode := TTimebarMode(Ini.SingTimebarMode);

  if (ScreenSong.Mode = smMedley) then
    CatSongs.Selected := PlaylistMedley.Song[PlaylistMedley.CurrentMedleySong-1];

  ScreenSong.MarkSongStarted;
  CurrentSong := CatSongs.Song[CatSongs.Selected];

  {for I := 0 to High(screenSingViewRef.StaticDuet) do
    Statics[screenSingViewRef.StaticDuet[I]].Visible := CurrentSong.isDuet;}
  Statics[screenSingViewRef.StaticLyricsBarDuet].Visible := CurrentSong.isDuet;

  Statics[screenSingViewRef.SongNameStatic].Visible := false;
  Text[screenSingViewRef.SongNameText].Visible := false;

  BadPlayer := 0;
  if (PlayersPlay > 0) and ((ScreenSong.Mode <> smNormal) or Party.bPartyGame) then
    BadPlayer := AudioInputProcessor.CheckPlayersConfig(PlayersPlay);

  if (BadPlayer <> 0) and CheckPlayerConfigOnNextSong then
  begin
    ScreenPopupError.ShowPopup(
        Format(Language.Translate('ERROR_PLAYER_NO_DEVICE_ASSIGNMENT'),
        [BadPlayer]));
    // do not show the warning again, unless something sets this to true again
    CheckPlayerConfigOnNextSong := false;
  end;

  if CurrentSong.isDuet then
    ConfigureVoiceLyrics
  else
  begin

    Lyrics.FontFamily := Ini.LyricsFont;
    Lyrics.FontStyle := Ini.LyricsStyle;

    Col := Theme.Sing.LyricActive;
    Lyrics.LineColor_act.R := Col.R;
    Lyrics.LineColor_act.G := Col.G;
    Lyrics.LineColor_act.B := Col.B;
    Lyrics.LineColor_act.A := 1;

    Col := Theme.Sing.LyricCurrent;
    Lyrics.LineColor_en.R := Col.R;
    Lyrics.LineColor_en.G := Col.G;
    Lyrics.LineColor_en.B := Col.B;
    Lyrics.LineColor_en.A := 1;

    Col := Theme.Sing.LyricNext;
    Lyrics.LineColor_dis.R := Col.R;
    Lyrics.LineColor_dis.G := Col.G;
    Lyrics.LineColor_dis.B := Col.B;
    Lyrics.LineColor_dis.A := 1;
  end;

  // deactivate pause
  Paused := false;

  LoadNextSong();

  Log.LogStatus('End', 'OnShow');
end;

procedure TScreenSingController.onShowFinish;
var
  PlayerIndex: integer;
begin
  if ScreenContinuousPlayback.Session.Active and
    (ScreenContinuousPlayback.Session.Stage = psAdvance) then Exit;
  // hide cursor on singscreen show
  Display.SetCursor;

  VoiceAssignments.SelectSong(CurrentSong);

  // clear the scores of all players
  for PlayerIndex := 0 to High(Player) do
    with Player[PlayerIndex] do
    begin
      ResetScores;

      ScoreLast      := 0;

      LastSentencePerfect := false;

      Track := VoiceAssignments.VoiceForPlayer(PlayerIndex, CurrentSong.VoiceCount);
    end;

  StopSingClicks;
  // prepare music
  // Important: AudioPlayback must not be initialized in onShow() as TScreenSong
  // uses stops AudioPlayback in onHide() which interferes with TScreenSings onShow.
  PlayMidi := false;
  MidiFadeIn := false;

  if (not Assigned(CurrentSong.Karaoke)) or (CurrentSong.Karaoke = PATH_NONE) then
    AudioPlayback.Open(CurrentSong.Path.Append(CurrentSong.Audio), nil)
  else
    AudioPlayback.Open(CurrentSong.Path.Append(CurrentSong.Audio), CurrentSong.Path.Append(CurrentSong.Karaoke));

  if ScreenContinuousPlayback.Session.Active and (AudioPlayback.Length <= 0) then
  begin
    SongError;
    Exit;
  end;

  if ScreenSong.Mode = smMedley then
    AudioPlayback.SetVolume(0.1)
  else
    AudioPlayback.SetVolume(1.0);
  //AudioPlayback.Position := CurrentSong.Start;
    if ((fStartTime < CurrentSong.Start) and (fStartTime > 0)) then
      AudioPlayback.StartTime := CurrentSong.Start;
  AudioPlayback.Position := LyricsState.GetCurrentTime();


  // set time
  if (CurrentSong.Finish > 0) then
    LyricsState.TotalTime := CurrentSong.Finish / 1000
  else
  begin
    LyricsState.TotalTime := AudioPlayback.Length;
  end;

  LyricsState.UpdateBeats();

  // synchronize music
  if Ini.SyncTo = Ord(stLyrics) then
    AudioPlayback.SetSyncSource(fLyricsSync)
  else
    AudioPlayback.SetSyncSource(nil);

  // synchronize lyrics (do not set this before AudioPlayback is initialized)
  if Ini.SyncTo = Ord(stMusic) then
    LyricsState.SetSyncSource(fMusicSync)
  else
    LyricsState.SetSyncSource(nil);

  // start lyrics
  LyricsState.Start(true);

  // start music
  if ScreenSong.Mode = smMedley then
    AudioPlayback.FadeIn(CurrentSong.Medley.FadeIn_time, 1.0)
  else
    AudioPlayback.Play();
  AnnounceRemoteSongStarted;

  // Send Score
  Act_MD5Song := CurrentSong.MD5;

  // start timer
  CountSkipTimeSet;

end;

procedure TScreenSingController.SongError();
var
  I, len:  integer;

begin
  if ScreenContinuousPlayback.Session.Active then
  begin
    ScreenContinuousPlayback.SongFailed;
    Exit;
  end;
  if ScreenSong.Mode <> smMedley then
  begin
    // error loading song -> go back to previous screen and show some error message
    Display.AbortScreenChange;

    // single song mode -> there is no screen to go back to, quit
    if Params.Song.IsSet then
    begin
      ExitCode := 1;
      Display.Fade := 0;
      Display.NextScreenWithCheck := nil;
      Display.CheckOK := true;
      Exit;
    end;

    // select new song in party mode
    if ScreenSong.Mode = smPartyClassic then
      ScreenSong.SelectRandomSong();

    if (Length(CurrentSong.LastError) > 0) then
      ScreenPopupError.ShowPopup(Format(Language.Translate(CurrentSong.LastError), [CurrentSong.ErrorLineNo]))
    else
      ScreenPopupError.ShowPopup(Language.Translate('ERROR_CORRUPT_SONG'));
    // FIXME: do we need this?
    CurrentSong.Path := CatSongs.Song[CatSongs.Selected].Path;
    Exit;
  end
  else
  begin
    if (PlaylistMedley.CurrentMedleySong<PlaylistMedley.NumMedleySongs) then
    begin
      //Error Loading Song in Medley Mode -> skip actual Medley Song an go on if possible
      len := Length(PlaylistMedley.Song);
      for I := PlaylistMedley.CurrentMedleySong - 1 to len - 2 do
        PlaylistMedley.Song[I] := PlaylistMedley.Song[I+1];

      SetLength(PlaylistMedley.Song, Len-1);
      Dec(PlaylistMedley.NumMedleySongs);
      LoadNextSong;
      Exit;
    end
    else
    begin
      if (PlaylistMedley.NumMedleySongs=1) then
      begin
        //Error Loading Song in Medley Mode -> Go back to Song Screen and Show some Error Message
        Display.AbortScreenChange;

        // select new song in party mode
        if ScreenSong.Mode = smPartyClassic then
          ScreenSong.SelectRandomSong();

        if (Length(CurrentSong.LastError) > 0) then
          ScreenPopupError.ShowPopup(Format(Language.Translate(CurrentSong.LastError), [CurrentSong.ErrorLineNo]))
        else
          ScreenPopupError.ShowPopup(Language.Translate('ERROR_CORRUPT_SONG'));

        // FIXME: do we need this?
        CurrentSong.Path := CatSongs.Song[CatSongs.Selected].Path;
        Exit;
      end
      else
      begin
        //Error Loading Song in Medley Mode -> Finish actual round
        len := Length(PlaylistMedley.Song);
        SetLength(PlaylistMedley.Song, len-1);
        Dec(PlaylistMedley.NumMedleySongs);
        Finish;
        Exit;
      end;
    end;
  end;
end;

procedure TScreenSingController.LoadNextSong();
var
  PlayerIndex: integer;
  Color:      TRGB;
  Index:      integer;
  VideoFile:  IPath;
  BgFile:     IPath;
  success:    boolean;
  AudioEnd:   real;

  function CurrentSongHasNotes: boolean;
  var
    TrackIndex: integer;
    LineIndex:  integer;
  begin
    Result := false;

    for TrackIndex := 0 to High(CurrentSong.Tracks) do
    begin
      for LineIndex := 0 to High(CurrentSong.Tracks[TrackIndex].Lines) do
      begin
        if Length(CurrentSong.Tracks[TrackIndex].Lines[LineIndex].Notes) > 0 then
        begin
          Result := true;
          Exit;
        end;
      end;
    end;
  end;

begin
  // background texture (garbage disposal)
  FreeAndNil(Tex_Background);

  // reset video playback engine
  fCurrentVideo := nil;

  // setup score manager
  Scores.ClearPlayers; // clear old player values
  Color.R := 0;
  Color.G := 0;
  Color.B := 0;

  // add new players
  for Index := 0 to PlayersPlay - 1 do
  begin
    Scores.AddPlayer(Tex_ScoreBG[Index], Color);
  end;

  Scores.Init; // get positions for players

  // FIXME: sets path and filename to ''
  ResetSingTemp;

  PlaylistMedley.ApplausePlayed := false;

  if ScreenSong.Mode = smMedley then
  begin
    if length(PlaylistMedley.Song) >= PlaylistMedley.CurrentMedleySong then
    begin
      CatSongs.Selected := PlaylistMedley.Song[PlaylistMedley.CurrentMedleySong-1];
    end
    else
    begin
      SongError;
      Exit;
    end;
  end;

  CurrentSong := CatSongs.Song[CatSongs.Selected];
  if (not Assigned(AudioPlayback)) or (AudioPlayback.Length = 0) or (CurrentSong.Path.Append(CurrentSong.Audio).ToNative <> AudioPlayback.GetFileName) then
  begin
    if (not Assigned(CurrentSong.Karaoke)) or (CurrentSong.Karaoke = PATH_NONE) then
      AudioPlayback.Open(CurrentSong.Path.Append(CurrentSong.Audio), nil)
    else
      AudioPlayback.Open(CurrentSong.Path.Append(CurrentSong.Audio), CurrentSong.Path.Append(CurrentSong.Karaoke));
  end;

  AudioEnd := 0;
  if Assigned(AudioPlayback) then
    AudioEnd := AudioPlayback.Length; // unfortunately only works when the song is already playing

  if (CurrentSong.Finish > 0) and (CurrentSong.Finish / 1000 < AudioEnd) then
    AudioEnd := CurrentSong.Finish / 1000;

  success := false;
  // FIXME: bad style, put the try-except into loadsong() and not here
  try
    success := CurrentSong.Analyse(false, false, true, AudioEnd, true); // and CurrentSong.LoadSong();
  except
    on E: EInOutError do Log.LogWarn(E.Message, 'TScreenSing.LoadNextSong');
  end;

  if (not success) then
  begin
    SongError();
    Exit;
  end;

  if ScreenSong.Mode = smMedley then
  begin
    if (CurrentSong.Medley.Source < msCalculated) or (Length(CurrentSong.Tracks) = 0) then
    begin
      SongError();
      Exit;
    end;

    if not CurrentSongHasNotes then
    begin
      SongError();
      Exit;
    end;
  end;

  if ScreenContinuousPlayback.Session.Active and
    ((AudioEnd <= 0) or not CurrentSongHasNotes) then
  begin
    SongError;
    Exit;
  end;

  ConfigureVoiceLyrics;
  CalculateStartTime;
  if (fStartTime < CurrentSong.Start) then
  begin
    fCountIn := true;
    AudioPlayback.Position := fStartTime;
    if (fStartTime > 0) then
      AudioPlayback.StartTime := CurrentSong.Start;
  end
  else
    fCountIn := false;

  // Set up Medley timings
  if ScreenSong.Mode = smMedley then
  begin
    CurrentSong.SetMedleyMode();

    if (PlaylistMedley.NumMedleySongs > 1) then
      Text[screenSingViewRef.SongNameText].Text := IntToStr(PlaylistMedley.CurrentMedleySong) +
        '/' + IntToStr(PlaylistMedley.NumMedleySongs) + ': ' +
        CurrentSong.Artist + ' - ' + CurrentSong.Title
    else
      Text[screenSingViewRef.SongNameText].Text := CurrentSong.Artist + ' - ' + CurrentSong.Title;

    //medley start and end timestamps
    StartNote := FindNote(CurrentSong.Medley.StartBeat - round(CurrentSong.BPM*CurrentSong.Medley.FadeIn_time/60));
    MedleyStart := GetTimeFromBeat(CurrentSong.Tracks[StartNote.track].Lines[StartNote.line].Notes[0].StartBeat);

    //check Medley-Start
    if (MedleyStart+CurrentSong.Medley.FadeIn_time*0.5>GetTimeFromBeat(CurrentSong.Medley.StartBeat)) then
      MedleyStart := GetTimeFromBeat(CurrentSong.Medley.StartBeat) - CurrentSong.Medley.FadeIn_time;
    if MedleyStart<0 then
      MedleyStart := 0;

    MedleyEnd := GetTimeFromBeat(CurrentSong.Medley.EndBeat) + CurrentSong.Medley.FadeOut_time;
  end;

  {*
   * == Background ==
   * We have five types of backgrounds:
   *   + Blank        : Nothing has been set, this is our fallback
   *   + Picture      : Picture has been set, and exists - otherwise we fallback
   *   + Video        : Video has been set, and exists - otherwise we fallback
   *   + Visualization: + Off                 : No visualization
   *                    + WhenNoVideo         : Overwrites blank and picture
   *                    + WhenNoVideoAndImage : Overwrites blank
   *                    + On                  : Overwrites blank, picture and video
   *}

  {*
   * set background to: video
   * Note: ffmpeg / this is also used for many background formats"
   *}
  fShowVisualization := false;
  VideoFile := CurrentSong.Path.Append(CurrentSong.Video);
  if (Ini.VideoEnabled = 1) and CurrentSong.Video.IsSet() and VideoFile.IsFile then
  begin
    fVideoClip := VideoPlayback.Open(VideoFile);
    if (fVideoClip <> nil) then
    begin
      fCurrentVideo := fVideoClip;
      fCurrentVideo.SetAspectCorrection(BackgroundAspectCorrection);
      fShowVisualization := false;
      if ScreenSong.Mode = smMedley then
        fCurrentVideo.Position := CurrentSong.VideoGAP + MedleyStart
      else
        fCurrentVideo.Position := CurrentSong.VideoGAP + CurrentSong.Start;
      fCurrentVideo.Play;
    end;
  end;

  {*
   * set background to: picture
   *}
  if (CurrentSong.Background.IsSet) then
  begin
    BgFile := CurrentSong.Path.Append(CurrentSong.Background);
    try
      Tex_Background := Renderer.LoadTexture(BgFile);
      Tex_BackgroundAspectRatio := Tex_Background.W / Tex_Background.H;
      fShowBackground := fCurrentVideo = nil;
    except
      Log.LogError('Background could not be loaded: ' + BgFile.ToNative);
      FreeAndNil(Tex_Background);
    end;
  end
  else
  begin
    FreeAndNil(Tex_Background);
  end;

  {*
   * set background to: visualization (Overwrites all)
   *}
  if (TVisualizerOption(Ini.VisualizerOption) in [voOn]) then
  begin
    fShowVisualization := true;
    fCurrentVideo := Visualization.Open(PATH_NONE);
    if (fCurrentVideo <> nil) then
      fCurrentVideo.Play;
  end

  {*
   * set background to: visualization (if video and image is not set)
   *}
  else if (TVisualizerOption(Ini.VisualizerOption) in [voWhenNoVideoAndImage]) and
     (not CurrentSong.Background.IsSet) and (fVideoClip = nil) then
  begin
    fShowVisualization := true;
    fCurrentVideo := Visualization.Open(PATH_NONE);
    if fCurrentVideo <> nil then
      fCurrentVideo.Play;
  end

  {*
   * set background to: visualization (Videos are still shown)
   *}
  else if ((TVisualizerOption(Ini.VisualizerOption) in [voWhenNoVideo]) and
     (fVideoClip = nil)) then
  begin
    fShowVisualization := true;
    fCurrentVideo := Visualization.Open(PATH_NONE);
    if fCurrentVideo <> nil then
      fCurrentVideo.Play;
  end;

  // prepare lyrics timer
  ScoringTailActive := false;
  Ini.ReloadDelays;
  LyricsState.Reset();

  if ScreenSong.Mode = smMedley then
  begin
    LyricsState.SetCurrentTime(MedleyStart);
    LyricsState.StartTime := CurrentSong.Gap;
    LyricsState.TotalTime := MedleyEnd;
  end
  else
  begin
    LyricsState.SetCurrentTime(fStartTime);
    LyricsState.StartTime := CurrentSong.Gap;
    if CurrentSong.Finish > 0 then
      LyricsState.TotalTime := CurrentSong.Finish / 1000
    else
      LyricsState.TotalTime := AudioPlayback.Length;
  end;

  LyricsState.UpdateBeats();

  for PlayerIndex := 0 to High(Player) do
    Player[PlayerIndex].DetectionReady := false;

  // prepare and start voice-capture
  if PlayersPlay > 0 then AudioInput.CaptureStart;

  // main text
  ClearLyricEngines;

  SetLength(NumEmptySentences, Length(CurrentSong.Tracks));
  for PlayerIndex := 0 to High(CurrentSong.Tracks) do
  begin
    if CurrentSong.isDuet then
    begin
      while not VoiceLyrics[PlayerIndex].IsQueueFull and
        (VoiceLyrics[PlayerIndex].LineCounter <= High(CurrentSong.Tracks[PlayerIndex].Lines)) do
        VoiceLyrics[PlayerIndex].AddLine(@CurrentSong.Tracks[PlayerIndex].Lines[
          VoiceLyrics[PlayerIndex].LineCounter]);
    end
    else
      while not Lyrics.IsQueueFull and (Lyrics.LineCounter <= High(CurrentSong.Tracks[0].Lines)) do
        Lyrics.AddLine(@CurrentSong.Tracks[0].Lines[Lyrics.LineCounter]);
    GoldenRec.SentenceChange(PlayerIndex);
    NumEmptySentences[PlayerIndex] := 0;
    for Index := 0 to High(CurrentSong.Tracks[PlayerIndex].Lines) do
      if CurrentSong.Tracks[PlayerIndex].Lines[Index].ScoreValue = 0 then
        Inc(NumEmptySentences[PlayerIndex]);
  end;

  eSongLoaded.CallHookChain(False);

  if (ScreenSong.Mode = smMedley) and (PlaylistMedley.CurrentMedleySong>1) then
    onShowFinish;
end;

// Forces the notes (lines) and lyrics to reset to the start of the song
procedure TScreenSingController.ResetLinesAndLyrics();
var
  i1: integer;

begin
  for i1 := 0 to High(CurrentSong.Tracks) do
  begin
    CurrentSong.Tracks[i1].CurrentLine := 0;
    OnSentenceChange(i1, 0);
  end;
end;

procedure TScreenSingController.ClearLyricEngines();
var I: integer;
begin
  Lyrics.Clear(CurrentSong.BPM);
  for I := 0 to High(VoiceLyrics) do VoiceLyrics[I].Clear(CurrentSong.BPM);
end;

procedure TScreenSingController.ClearVoiceLyrics;
var I: integer;
begin
  for I := 0 to High(VoiceLyrics) do VoiceLyrics[I].Free;
  SetLength(VoiceLyrics, 0);
end;

procedure TScreenSingController.ConfigureVoiceLyrics;
var I: integer;
  Col: TRGB;
begin
  ClearVoiceLyrics;
  SetLength(VoiceLyrics, CurrentSong.VoiceCount);
  for I := 0 to High(VoiceLyrics) do
  begin
    VoiceLyrics[I] := TLyricEngine.Create(0, 0, 1, 1, 0, 0, 1, 1);
    VoiceLyrics[I].FontFamily := Ini.LyricsFont;
    VoiceLyrics[I].FontStyle := Ini.LyricsStyle;
    Col := GetPlayerColor(Ini.PlayerColor[I mod UIni.IMaxPlayerCount]);
    if not Theme.Sing.LyricUsePlayerColors then Col := Theme.Sing.LyricActive;
    VoiceLyrics[I].LineColor_act.R := Col.R;
    VoiceLyrics[I].LineColor_act.G := Col.G;
    VoiceLyrics[I].LineColor_act.B := Col.B;
    VoiceLyrics[I].LineColor_act.A := 1;
    Col := Theme.Sing.LyricCurrent;
    VoiceLyrics[I].LineColor_en.R := Col.R;
    VoiceLyrics[I].LineColor_en.G := Col.G;
    VoiceLyrics[I].LineColor_en.B := Col.B;
    VoiceLyrics[I].LineColor_en.A := 1;
    Col := Theme.Sing.LyricNext;
    VoiceLyrics[I].LineColor_dis.R := Col.R;
    VoiceLyrics[I].LineColor_dis.G := Col.G;
    VoiceLyrics[I].LineColor_dis.B := Col.B;
    VoiceLyrics[I].LineColor_dis.A := 1;
    VoiceLyrics[I].PreviewAlpha := Theme.Sing.VoicePreviewAlpha;
  end;
end;

procedure TScreenSingController.LayoutVoiceLyrics;
var
  I, J, FirstPlayer, LocalPlayers, Count, Bank, CenterBank: integer;
  PlayerBanks: array of integer;
  Used: array[0..1] of boolean;
  AssignedElsewhere: boolean;
  CenterY: real;
begin
  FirstPlayer := GetFirstPlayerIndexForScreen(PlayersPlay, Screens, ScreenAct);
  LocalPlayers := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
  SetLength(PlayerBanks, LocalPlayers);
  CenterBank := 0;
  for J := 0 to LocalPlayers - 1 do
  begin
    with Statics[screenSingViewRef.PlayerFrameSlots[LocalPlayers, J]].Texture do
      CenterY := Y + H / 2;
    if CenterY < RenderH / 2 - 0.01 then PlayerBanks[J] := 0
    else if CenterY > RenderH / 2 + 0.01 then PlayerBanks[J] := 1
    else
    begin
      PlayerBanks[J] := CenterBank;
      CenterBank := 1 - CenterBank;
    end;
  end;
  SetLength(DisplayedVoices, 0);
  SetLength(DisplayedVoiceBanks, 0);
  VoiceBankCounts[0] := 0;
  VoiceBankCounts[1] := 0;
  for I := 0 to High(VoiceLyrics) do
  begin
    Used[0] := false;
    Used[1] := false;
    AssignedElsewhere := false;
    for J := 0 to PlayersPlay - 1 do
      if Player[J].Track = I then
      begin
        if (J >= FirstPlayer) and (J < FirstPlayer + LocalPlayers) then
          Used[PlayerBanks[J - FirstPlayer]] := true
        else AssignedElsewhere := true;
      end;
    // An unassigned song part must not disappear. Shared voices can appear in both halves.
    if not (Used[0] or Used[1] or AssignedElsewhere) then
    begin
      if VoiceBankCounts[0] <= VoiceBankCounts[1] then Used[0] := true
      else Used[1] := true;
    end;
    for Bank := 0 to 1 do
      if Used[Bank] then
      begin
        Inc(VoiceBankCounts[Bank]);
        Count := Length(DisplayedVoices);
        SetLength(DisplayedVoices, Count + 1);
        SetLength(DisplayedVoiceBanks, Count + 1);
        DisplayedVoices[Count] := I;
        DisplayedVoiceBanks[Count] := Bank;
      end;
  end;
end;

procedure TScreenSingController.PositionVoiceLyrics(DisplayIndex: integer);
var
  I, Count, Columns, Rows, Bank, Cell: integer;
  X, Y, W, H, Gutter: real;
  Engine: TLyricEngine;
begin
  Engine := VoiceLyrics[DisplayedVoices[DisplayIndex]];
  Bank := DisplayedVoiceBanks[DisplayIndex];
  Count := VoiceBankCounts[Bank];
  GetVoiceGrid(Count * 2, Columns, Rows);
  Cell := 0;
  for I := 0 to DisplayIndex - 1 do
    if DisplayedVoiceBanks[I] = Bank then Inc(Cell);
  Engine.Compact := Count > 1;
  if Bank = 0 then
  begin
    X := Theme.LyricBarDuetP1.UpperX;
    Y := Theme.LyricBarDuetP1.UpperY;
    W := Theme.LyricBarDuetP1.UpperW;
    H := Theme.LyricBarDuetP1.LowerY + Theme.LyricBarDuetP1.LowerH - Y;
  end
  else
  begin
    X := Theme.LyricBarDuetP2.UpperX;
    Y := Theme.LyricBarDuetP2.UpperY;
    W := Theme.LyricBarDuetP2.UpperW;
    H := Theme.LyricBarDuetP2.LowerY + Theme.LyricBarDuetP2.LowerH - Y;
  end;
  Gutter := 0;
  if Theme.Sing.VoiceLabelVisible then Gutter := Theme.Sing.VoiceLabelGutter;
  Engine.UpperLineX := X + (Cell mod Columns) * W / Columns + Gutter;
  Engine.UpperLineY := Y + (Cell div Columns) * H / Rows;
  Engine.UpperLineW := Max(1, W / Columns - Gutter - Theme.Sing.VoiceCellPadding);
  Engine.UpperLineH := H / Rows;
  Engine.LowerLineX := Engine.UpperLineX;
  Engine.LowerLineW := Engine.UpperLineW;
  Engine.LowerLineY := Engine.UpperLineY;
  Engine.LowerLineH := Engine.UpperLineH;
  if not Engine.Compact then
  begin
    Engine.UpperLineH := H / 2;
    Engine.LowerLineY := Y + H / 2;
    Engine.LowerLineH := H / 2;
  end;
  Engine.UpdateLineMetrics;
end;

procedure TScreenSingController.CalculateStartTime;
var
  I, J, StartBeat: integer;
begin
  StartBeat := MaxInt;
  for I := Low(CurrentSong.Tracks) to High(CurrentSong.Tracks) do
    for J := 0 to High(CurrentSong.Tracks[I].Lines) do
      if Length(CurrentSong.Tracks[I].Lines[J].Notes) > 0 then
      begin
        StartBeat := Min(StartBeat, CurrentSong.Tracks[I].Lines[J].Notes[0].StartBeat);
        Break;
      end;
  if StartBeat = MaxInt then StartBeat := 0;
  fFirstNote := (CurrentSong.GAP / 1000) + ((StartBeat * 60) / CurrentSong.BPM);
  if ((fFirstNote - CurrentSong.Start) < MINIMUM_START_TIME) then
    fStartTime := fFirstNote - MINIMUM_START_TIME
  else
    fStartTime := CurrentSong.Start;
end;

procedure TScreenSingController.AnnounceRemoteSongStarted;
var I: integer;
begin
  for I := 0 to High(Player) do Player[I].InputSource := Ord(PlayerInputSource(I));
  Inc(RemoteSongSeq);
  LastRemoteScoreSnapshotTick := 0;
  RemoteBridgeIPC.SendSongStarted(
    RemoteSongSeq,
    CatSongs.Selected,
    RemoteMediaStartUs,
    RemoteSongDurationUs,
    CurrentSong.Title,
    CurrentSong.Artist
  );
  RemoteInputProcessor.AcceptingInput := true;
  RemoteBridgeIPC.SendGameState('singing', RemoteSongSeq, 0);
  SendRemoteScoreSheet;
  SendRemoteLyrics;
  SendRemoteScoreSnapshot(true);
end;

procedure TScreenSingController.AnnounceRemoteSongPaused;
begin
  if (RemoteSongSeq > 0) then
  begin
    RemoteInputProcessor.AcceptingInput := false;
    RemoteBridgeIPC.SendSongPaused(RemoteSongSeq, RemoteMediaStartUs, RemoteSongDurationUs);
    RemoteBridgeIPC.SendGameState('paused', RemoteSongSeq, 0);
  end;
end;

procedure TScreenSingController.AnnounceRemoteSongResumed;
begin
  if (RemoteSongSeq > 0) then
  begin
    RemoteInputProcessor.AcceptingInput := true;
    RemoteBridgeIPC.SendSongResumed(RemoteSongSeq, RemoteMediaStartUs, RemoteSongDurationUs);
    RemoteBridgeIPC.SendGameState('singing', RemoteSongSeq, 0);
  end;
end;

procedure TScreenSingController.AnnounceRemoteSongEnded;
var I: integer; Source: TPlayerInputSource;
begin
  for I := 0 to High(Player) do
  begin
    Source := PlayerInputSource(I);
    if Source <> pisNone then Player[I].InputSource := Ord(Source);
  end;
  if (RemoteSongSeq > 0) then
  begin
    RemoteInputProcessor.AcceptingInput := false;
    SendRemoteScoreSnapshot(true);
    RemoteBridgeIPC.SendSongEnded(RemoteSongSeq, RemoteMediaStartUs, RemoteSongDurationUs);
    RemoteBridgeIPC.SendGameState('song_ended', RemoteSongSeq, 0);
  end;
end;

procedure TScreenSingController.AnnounceRemoteSongPosition(const Reason: UTF8String);
begin
  if (RemoteSongSeq <= 0) then
    Exit;

  RemoteBridgeIPC.SendJsonMessage(
    '{"type":"song.position","protocol":1' +
    ',"songSeq":' + IntToStr(RemoteSongSeq) +
    ',"mediaStartUs":' + IntToStr(RemoteMediaStartUs) +
    ',"durationUs":' + IntToStr(RemoteSongDurationUs) +
    ',"reason":"' + RemoteJsonEscape(Reason) + '"' +
    '}'
  );
end;

procedure TScreenSingController.SendRemoteLyrics;
var
  TrackIndex: integer;
  LineIndex: integer;
  NoteIndex: integer;
  TracksJson: string;
  NotesJson: string;
  Note: PLineFragment;
  LyricText: UTF8String;
begin
  if (RemoteSongSeq <= 0) or (Length(CurrentSong.Tracks) = 0) then
    Exit;

  TracksJson := '[';
  for TrackIndex := 0 to High(CurrentSong.Tracks) do
  begin
    if (TrackIndex > 0) then
      TracksJson := TracksJson + ',';

    LineIndex := CurrentSong.Tracks[TrackIndex].CurrentLine;
    if (LineIndex >= 0) and (LineIndex <= CurrentSong.Tracks[TrackIndex].High) then
      LyricText := CurrentSong.Tracks[TrackIndex].Lines[LineIndex].Lyric
    else
      LyricText := '';

    NotesJson := '[';
    if (LineIndex >= 0) and (LineIndex <= CurrentSong.Tracks[TrackIndex].High) then
      for NoteIndex := 0 to CurrentSong.Tracks[TrackIndex].Lines[LineIndex].HighNote do
      begin
        Note := @CurrentSong.Tracks[TrackIndex].Lines[LineIndex].Notes[NoteIndex];
        if NoteIndex > 0 then NotesJson := NotesJson + ',';
        NotesJson := NotesJson + '{"text":"' + RemoteJsonEscape(Note.Text) +
          '","startUs":' + IntToStr(Round(GetTimeFromBeat(Note.StartBeat) * 1000000)) +
          ',"endUs":' + IntToStr(Round(GetTimeFromBeat(Note.StartBeat + Note.Duration) * 1000000)) + '}';
      end;
    NotesJson := NotesJson + ']';

    TracksJson := TracksJson +
      '{"track":' + IntToStr(TrackIndex) +
      ',"line":' + IntToStr(LineIndex) +
      ',"text":"' + RemoteJsonEscape(LyricText) + '","notes":' + NotesJson + '}';
  end;
  TracksJson := TracksJson + ']';

  RemoteBridgeIPC.SendJsonMessage(
    '{"type":"song.lyrics","protocol":1' +
    ',"songSeq":' + IntToStr(RemoteSongSeq) +
    ',"mediaStartUs":' + IntToStr(RemoteMediaStartUs) +
    ',"tracks":' + TracksJson +
    '}'
  );
end;

procedure TScreenSingController.SendRemoteScoreSheet;
var
  TrackIndex: integer;
  LineIndex: integer;
  NoteIndex: integer;
  Beat: integer;
  TracksJson: string;
  BeatsJson: string;
  NeedComma: boolean;
  Note: PLineFragment;
begin
  if (RemoteSongSeq <= 0) or (Length(CurrentSong.Tracks) = 0) then
    Exit;

  TracksJson := '[';
  for TrackIndex := 0 to High(CurrentSong.Tracks) do
  begin
    if (TrackIndex > 0) then
      TracksJson := TracksJson + ',';

    BeatsJson := '[';
    NeedComma := false;
    for LineIndex := 0 to CurrentSong.Tracks[TrackIndex].High do
    begin
      for NoteIndex := 0 to CurrentSong.Tracks[TrackIndex].Lines[LineIndex].HighNote do
      begin
        Note := @CurrentSong.Tracks[TrackIndex].Lines[LineIndex].Notes[NoteIndex];
        if (Note.NoteType = ntFreestyle) or (Note.Duration <= 0) then
          Continue;

        for Beat := Note.StartBeat to Note.StartBeat + Note.Duration - 1 do
        begin
          if NeedComma then
            BeatsJson := BeatsJson + ',';
          NeedComma := true;
          BeatsJson := BeatsJson +
            '[' + IntToStr(Beat) +
            ',' + IntToStr(Note.Tone) +
            ',' + IntToStr(Ord(Note.NoteType)) +
            ']';
        end;
      end;
    end;
    BeatsJson := BeatsJson + ']';

    TracksJson := TracksJson +
      '{"track":' + IntToStr(TrackIndex) +
      ',"beats":' + BeatsJson +
      '}';
  end;
  TracksJson := TracksJson + ']';

  RemoteBridgeIPC.SendJsonMessage(
    '{"type":"score.sheet"' +
    ',"tracks":' + TracksJson +
    '}'
  );
end;

procedure TScreenSingController.SendRemoteScoreSnapshot(Force: boolean);
var
  Tick: cardinal;
  I: integer;
  PlayersJson: string;
begin
  if (RemoteSongSeq <= 0) then
    Exit;

  Tick := SDL_GetTicks;
  if (not Force) and (Tick - LastRemoteScoreSnapshotTick < REMOTE_SCORE_SNAPSHOT_MS) then
    Exit;

  LastRemoteScoreSnapshotTick := Tick;
  PlayersJson := '[';
  for I := 0 to High(Player) do
  begin
    if (I > 0) then
      PlayersJson := PlayersJson + ',';
    PlayersJson := PlayersJson +
      '{"slot":' + IntToStr(I + 1) +
      ',"score":' + IntToStr(Player[I].ScoreInt) +
      ',"scoreLine":' + IntToStr(Player[I].ScoreLineInt) +
      ',"scoreGolden":' + IntToStr(Player[I].ScoreGoldenInt) +
      ',"scoreTotal":' + IntToStr(Player[I].ScoreTotalInt) +
      '}';
  end;
  PlayersJson := PlayersJson + ']';

  RemoteBridgeIPC.SendJsonMessage(
    '{"type":"score.snapshot","protocol":1' +
    ',"songSeq":' + IntToStr(RemoteSongSeq) +
    ',"mediaStartUs":' + IntToStr(RemoteMediaStartUs) +
    ',"durationUs":' + IntToStr(RemoteSongDurationUs) +
    ',"players":' + PlayersJson +
    '}'
  );
end;

function TScreenSingController.RemoteMediaStartUs: int64;
begin
  Result := Round(AudioPlayback.Position * 1000000);
  if (Result < 0) then
    Result := 0;
end;

function TScreenSingController.RemoteSongDurationUs: int64;
var
  Duration: real;
begin
  Duration := LyricsState.TotalTime;
  if (Duration <= 0) and Assigned(AudioPlayback) then
    Duration := AudioPlayback.Length;
  Result := Round(Duration * 1000000);
  if (Result < 0) then
    Result := 0;
end;

procedure TScreenSingController.ClearSettings;
var DisplayOptions: TContinuousDisplay;
begin
  Settings.Finish := False;
  Settings.OscilloscopeVisible := Boolean(Ini.Oscilloscope);
  Settings.LyricsVisible := True;
  AllNotesVisible(PlayersPlay > 0);
  Settings.ScoresVisible := PlayersPlay > 0;
  Settings.AvatarsVisible := PlayersPlay > 0;
  Settings.TimeBarVisible := True;
  Settings.InputVisible := PlayersPlay > 0;
  if PlayersPlay = 0 then Settings.OscilloscopeVisible := false;
  Settings.PlayerEnabled := high(Integer);
  Settings.SoundEnabled := True;
  Settings.FeedbackVisible := PlayersPlay > 0;
  if Assigned(ScreenContinuousPlayback) and (ScreenSong.Mode = smNormal) then
  begin
    DisplayOptions := ContinuousDisplay(PlayersPlay > 0,
      ScreenContinuousPlayback.SongDisplay, ScreenContinuousPlayback.SingingDisplay);
    Settings.LyricsVisible := DisplayOptions.Lyrics;
    Settings.TimeBarVisible := DisplayOptions.Progress;
    AllNotesVisible(DisplayOptions.Notes);
    Settings.InputVisible := DisplayOptions.Notes;
    Settings.OscilloscopeVisible := Settings.OscilloscopeVisible and DisplayOptions.Notes;
    Settings.ScoresVisible := DisplayOptions.PlayerInfo;
    Settings.AvatarsVisible := DisplayOptions.PlayerInfo;
    Settings.FeedbackVisible := DisplayOptions.Feedback;
  end;
end;

procedure TScreenSingController.AllNotesVisible(visible: boolean);
var
  I: integer;
begin
  for I := 0 to High(ScreenSing.Settings.NotesVisible) do begin
    ScreenSing.Settings.NotesVisible[I] := visible;
  end;
end;

{ applies changes of settings record }
procedure TScreenSingController.ApplySettings;
begin
  //
end;

procedure TScreenSingController.EndSong;
begin
  Settings.Finish := True;
end;

procedure TScreenSingController.OnHide;
begin
  StopSingClicks;
  RemoteBridgeIPC.SendJsonMessage(
    '{"type":"audio.stop","protocol":1,"reason":"sing_screen_left"}'
  );


  // close video files
  fVideoClip := nil;
  fCurrentVideo := nil;

  // background texture
  FreeAndNil(Tex_Background);
  if fShowWebcam then
        begin
          Webcam.Release;
          fShowWebCam:=false;
        end;
  Background.OnFinish;
  Display.SetCursor;
end;

function TScreenSingController.Draw: boolean;
begin
  SendRemoteScoreSnapshot(false);
  Result := true;
  if not ScreenContinuousPlayback.Session.Active or
    (ScreenContinuousPlayback.Session.Stage <> psAdvance) then
    Result := screenSingViewRef.Draw();
  if Display.CurrentScreen = @ScreenSing then ScreenContinuousPlayback.Update;

end;

function TScreenSingController.FinishedMusic: boolean;
begin
  Result := AudioPlayback.Finished;
end;

procedure TScreenSingController.ResumeAfterScoringTail;
begin
  if not ScoringTailActive then Exit;
  ScoringTailActive := false;
  if Ini.SyncTo = Ord(stMusic) then LyricsState.SetSyncSource(fMusicSync);
  if Ini.SyncTo = Ord(stLyrics) then AudioPlayback.SetSyncSource(fLyricsSync);
  if not Paused then AudioPlayback.Play;
end;

function TScreenSingController.ContinueDelayedScoring: boolean;
var
  PlayerIndex, TrackIndex, LineIndex, LastBeat, TargetBeat: integer;
  EndTime: real;
begin
  Result := false;
  if Settings.Finish or FadeOut then Exit;
  EndTime := AudioPlayback.Length;
  if CurrentSong.Finish > 0 then
    EndTime := Min(EndTime, CurrentSong.Finish / 1000);
  if ScreenSong.Mode = smMedley then
    EndTime := Min(EndTime, MedleyEnd);
  ScoringTailEndBeat := Floor(GetMidBeat(EndTime - CurrentSong.Gap / 1000));
  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    if not Player[PlayerIndex].DetectionReady or
      (Player[PlayerIndex].DetectionDelay <= 0) then Continue;
    TrackIndex := 0;
    if CurrentSong.isDuet then
      TrackIndex := Player[PlayerIndex].Track;
    LastBeat := Low(integer);
    for LineIndex := 0 to CurrentSong.Tracks[TrackIndex].High do
      with CurrentSong.Tracks[TrackIndex].Lines[LineIndex] do
        if HighNote >= 0 then
          LastBeat := Max(LastBeat, Notes[HighNote].StartBeat + Notes[HighNote].Duration);
    TargetBeat := Min(LastBeat, ScoringTailEndBeat);
    if Player[PlayerIndex].DetectionBeat < TargetBeat then
      Result := true;
  end;
  if not Result then Exit;
  if Paused then Exit;
  if not ScoringTailActive then
  begin
    ScoringTailActive := true;
    // Let scoring catch up independently of playback. A song with an explicit
    // finish point can still have audio to carry into the results screens.
    // ScoringTailEndBeat keeps that audio from extending the scoring range.
    AudioPlayback.SetSyncSource(nil);
    LyricsState.SetSyncSource(nil);
    LyricsState.SetCurrentTime(EndTime);
    LyricsState.Start;
  end;
  Sing(Self);
end;

procedure TScreenSingController.Finish;
var
  I, J:     integer;
  len, num: integer;

begin
  if ScreenContinuousPlayback.Session.Active and
    (ScreenContinuousPlayback.Session.Stage <> psSong) then Exit;
  if FadeOut then Exit;
  AnnounceRemoteSongEnded;
  Log.LogStatus('TScreenSingController.Finish', 'TScreenSingController.Finish');
  if PlayersPlay > 0 then AudioInput.CaptureStop;

  AudioPlayback.SetSyncSource(nil);

  if (PlayersPlay > 0) and (ScreenSong.Mode = smNormal) and SungToEnd and
     not PlaybackSeeked then
  begin
    SaveLocalScores;

    if (Length(DllMan.Websites) > 0) then
    begin
      AutoSendScore;
      AutoSaveScore;
    end;
  end;

  LyricsState.Stop();
  LyricsState.SetSyncSource(nil);

  // kill all stars and effects
  GoldenRec.KillAll;

  if (PlayersPlay > 0) and (Ini.SavePlayback = 1) then
  begin
    Log.BenchmarkStart(0);
    Log.LogVoice(0);
    if (PlayersPlay > 1) then
      Log.LogVoice(1);
    if (PlayersPlay > 2) then
      Log.LogVoice(2);
    Log.BenchmarkEnd(0);
    Log.LogBenchmark('Creating files', 0);
  end;

  SetFontItalic(false);

  if ScreenSong.Mode = smMedley then
  begin
    if not FadeOut then
    begin
      if Length(PlaylistMedley.Stats) = 0 then
        UpdateMedleyStats(false);

      for I := 0 to PlayersPlay - 1 do
        PlaylistMedley.Stats[Length(PlaylistMedley.Stats) - 1].Player[I] := Player[I];

      Inc(PlaylistMedley.CurrentMedleySong);
      if PlaylistMedley.CurrentMedleySong <= PlaylistMedley.NumMedleySongs then
      begin
        LoadNextSong;
      end
      else
      begin
        //build sums
        len := Length(PlaylistMedley.Stats);
        num := PlaylistMedley.NumPlayer;

        SetLength(PlaylistMedley.Stats, len + 1);
        SetLength(PlaylistMedley.Stats[len].Player, num);
        for I := 0 to num - 1 do
        begin
          PlaylistMedley.Stats[len].Player[I].Name := PlaylistMedley.Stats[0].Player[I].Name;
          PlaylistMedley.Stats[len].Player[I].Level := PlaylistMedley.Stats[0].Player[I].Level;
          PlaylistMedley.Stats[len].Player[I].TeamID := PlaylistMedley.Stats[0].Player[I].TeamID;
          PlaylistMedley.Stats[len].Player[I].PlayerID := PlaylistMedley.Stats[0].Player[I].PlayerID;
          PlaylistMedley.Stats[len].Player[I].HighNote := -1;
          PlaylistMedley.Stats[len].Player[I].LengthNote := 0;
          SetLength(PlaylistMedley.Stats[len].Player[I].Note, 0);
          PlaylistMedley.Stats[len].Player[I].ResetScores;
        end;

        for J := 0 to len - 1 do
        begin
          for I := 0 to num - 1 do
          begin
            PlaylistMedley.Stats[len].Player[I].Score :=
              PlaylistMedley.Stats[len].Player[I].Score +
              PlaylistMedley.Stats[J].Player[I].Score;

            PlaylistMedley.Stats[len].Player[I].ScoreLine :=
              PlaylistMedley.Stats[len].Player[I].ScoreLine +
              PlaylistMedley.Stats[J].Player[I].ScoreLine;

            PlaylistMedley.Stats[len].Player[I].ScoreGolden :=
              PlaylistMedley.Stats[len].Player[I].ScoreGolden +
              PlaylistMedley.Stats[J].Player[I].ScoreGolden;
          end; //of for I
        end; //of for J

        //build mean on sum
        for I := 0 to num - 1 do
        begin
          PlaylistMedley.Stats[len].Player[I].Score := round(
            PlaylistMedley.Stats[len].Player[I].Score / len);

          PlaylistMedley.Stats[len].Player[I].ScoreLine := round(
            PlaylistMedley.Stats[len].Player[I].ScoreLine / len);

          PlaylistMedley.Stats[len].Player[I].ScoreGolden := round(
            PlaylistMedley.Stats[len].Player[I].ScoreGolden / len);
        end;

        Party.CallAfterSing;
        FadeOut:=true;
      end;
    end;
  end
  else
  begin
    SetLength(PlaylistMedley.Stats, 1);
    SetLength(PlaylistMedley.Stats[0].Player, PlayersPlay);
    for I := 0 to PlayersPlay - 1 do
      PlaylistMedley.Stats[0].Player[I] := Player[I];

    PlaylistMedley.Stats[0].SongArtist := CurrentSong.Artist;
    PlaylistMedley.Stats[0].SongTitle := CurrentSong.Title;

    if not FadeOut then
    begin
      // single song mode -> quit instead of showing the score screen
      if Params.Song.IsSet then
      begin
        Display.Fade := 0;
        Display.NextScreenWithCheck := nil;
        Display.CheckOK := true;
      end
      else if ScreenContinuousPlayback.Session.Active then
        ScreenContinuousPlayback.SongFinished
      else if PlayersPlay = 0 then
        FadeTo(@ScreenSong)
      else if (ScreenSong.Mode = smNormal) and ScreenContinuousPlayback.BeginNormalResults then
      begin
        // The configured result policy owns the transition.
      end
      else
        Party.CallAfterSing;
    end;

    FadeOut := true;
  end;

end;

procedure TScreenSingController.OnSentenceEnd(Track: integer; SentenceIndex: cardinal; OnlyPlayer: integer); //ToDo: split and redo
var
  PlayerIndex: integer;
  CurrentPlayer: PPLayer;
  CurrentScore: real;
  Line:      PLine;
  LinePerfection: real;  // perfection of singing performance on the current line
  Rating:    integer;
  LineScore: real;
  LineBonus: real;
  MaxSongScore: integer; // max. points for the song (without line bonus)
  MaxLineScore: real;    // max. points for the current line
const
  // TODO: move this to a better place
  MAX_LINE_RATING = 8;        // max. rating for singing performance
begin
  Line := @CurrentSong.Tracks[Track].Lines[SentenceIndex];

  // check for empty sentence
  if Line.ScoreValue <= 0 then
    Exit;

  // set max song score
  MaxSongScore := MAX_SONG_SCORE - MAX_SONG_LINE_BONUS;

  // Note: ScoreValue is the sum of all note values of the song
  MaxLineScore := MaxSongScore * (Line.ScoreValue / CurrentSong.Tracks[Track].ScoreValue);

  for PlayerIndex := 0 to High(Player) do
  begin
    if ((OnlyPlayer < 0) or (OnlyPlayer = PlayerIndex)) and
       ((not CurrentSong.isDuet) or (Player[PlayerIndex].Track = Track)) then
    begin
      CurrentPlayer := @Player[PlayerIndex];
      CurrentScore  := CurrentPlayer.Score + CurrentPlayer.ScoreGolden;

      // line bonus

      // points for this line
      if not GetPlayerSentenceScore(PlayerIndex, Track, SentenceIndex, LineScore) then
        LineScore := CurrentScore - CurrentPlayer.ScoreLast;

      // check for lines with low points
      if MaxLineScore <= 2 then
        LinePerfection := 1
      else
        // determine LinePerfection
        // Note: the "+2" extra points are a little bonus so the player does not
        // have to be that perfect to reach the bonus steps.
        LinePerfection := LineScore / (MaxLineScore - 2);

      // clamp LinePerfection to range [0..1]
      if LinePerfection < 0 then
        LinePerfection := 0
      else if LinePerfection > 1 then
        LinePerfection := 1;

      // line-bonus points (same for each line, no matter how long the line is)
      LineBonus := MAX_SONG_LINE_BONUS / (Length(CurrentSong.Tracks[Track].Lines) -
        NumEmptySentences[Track]);
      // apply line-bonus
      CurrentPlayer.ScoreLine :=
        CurrentPlayer.ScoreLine + LineBonus * LinePerfection;

      // spawn rating pop-up
      Rating := Round(LinePerfection * MAX_LINE_RATING);
      Scores.SpawnPopUp(PlayerIndex, Rating, CurrentPlayer.ScoreTotalInt);

      if (Scores <> nil) then
        Scores.SetRemainingScore(PlayerIndex,
          CurrentPlayer.ScorePerfectRemaining / MAX_SONG_SCORE,
          CurrentPlayer.Score + CurrentPlayer.ScoreGolden + CurrentPlayer.ScoreLine);

      // PerfectLineTwinkle (effect), part 1
      if Ini.EffectSing = 1 then
        CurrentPlayer.LastSentencePerfect := (LinePerfection >= 1);

      // refresh last score
      CurrentPlayer.ScoreLast := CurrentScore;
    end;
  end;

  // PerfectLineTwinkle (effect), part 2
  if Ini.EffectSing = 1 then
  begin
    GoldenRec.SpawnPerfectLineTwinkle;

    for PlayerIndex := 0 to High(Player) do
    begin
      CurrentPlayer := @Player[PlayerIndex];
      CurrentPlayer.LastSentencePerfect := false;
    end;
  end;

end;

 // Called on sentence change
 // SentenceIndex: index of the new active sentence
procedure TScreenSingController.OnSentenceChange(Track: integer; SentenceIndex: cardinal);  //ToDo: split and redo
var
  tmp_Lyric: TLyricEngine;
begin
  // goldenstarstwinkle
  GoldenRec.SentenceChange(Track);

  if CurrentSong.isDuet then
    tmp_Lyric := VoiceLyrics[Track]
  else
    tmp_Lyric := Lyrics;

  // fill lyrics queue and set upper line to the current sentence
  while (tmp_Lyric.GetUpperLineIndex() < SentenceIndex) or
    (not tmp_Lyric.IsQueueFull) do
  begin
    // add the next line to the queue or a dummy if no more lines are available
    if (tmp_Lyric.LineCounter <= High(CurrentSong.Tracks[Track].Lines)) then
    begin
      tmp_Lyric.AddLine(@CurrentSong.Tracks[Track].Lines[tmp_Lyric.LineCounter]);
    end
    else
      tmp_Lyric.AddLine(nil);
  end;

  SendRemoteLyrics;
end;

function TLyricsSyncSource.GetClock(): real;
begin
  Result := LyricsState.GetCurrentTime();
end;

function TMusicSyncSource.GetClock(): real;
begin
  Result := AudioPlayback.Position;
end;

procedure TScreenSingController.UpdateMedleyStats(medley_end: boolean);   //TODO: view or controller? unsure
var
  len, num, I : integer;

begin
  len := Length(PlaylistMedley.Stats);
  num := PlaylistMedley.NumPlayer;

  if (PlaylistMedley.CurrentMedleySong > len) and
    (PlaylistMedley.CurrentMedleySong <= PlaylistMedley.NumMedleySongs) then
  begin
    inc(len);
    SetLength(PlaylistMedley.Stats, len);
    SetLength(PlaylistMedley.Stats[len - 1].Player, num);
    PlaylistMedley.Stats[len-1].SongArtist := CurrentSong.Artist;
    PlaylistMedley.Stats[len-1].SongTitle := CurrentSong.Title;
  end;

  if PlaylistMedley.CurrentMedleySong <= PlaylistMedley.NumMedleySongs then
    for I := 0 to num - 1 do
      PlaylistMedley.Stats[len - 1].Player[I] := Player[I];

  if medley_end and not PlaylistMedley.ApplausePlayed and
    (PlaylistMedley.CurrentMedleySong<=PlaylistMedley.NumMedleySongs) then
  begin
    PlaylistMedley.ApplausePlayed:=true;

    AudioPlayback.Fade(CurrentSong.Medley.FadeOut_time, 0.1);
    AudioPlayback.PlaySound(SoundLib.Applause);
  end;
end;


procedure TScreenSingController.SaveLocalScores;
var
  I: integer;
  Sung: boolean;
  Name1, Name2, CombinedName: UTF8String;
  Score1, Score2, CombinedScore, CombinedMask: integer;
begin
  Sung := false;

  if ScreenSing.SungToEnd then
  begin
    if not CurrentSong.isDuet or (Ini.DuetScores in [1, 3]) then
    begin
      for I := 0 to PlayersPlay - 1 do
      begin
        Score1 := Round(Player[I].ScoreTotalInt);
        if Score1 > 0 then
        begin
          DataBase.AddScore(CurrentSong, Player[I].Level,
              Length(CurrentSong.Tracks), 1 shl Player[I].Track,
              Player[I].Name, Score1);
          Sung := true;
        end;
      end;
    end;

    if CurrentSong.isDuet and (Ini.DuetScores in [2, 3]) then
    begin
      I := 0;
      while I < PlayersPlay - 1 do
      begin
        if (Player[I].Level = Player[I + 1].Level) and
          (Player[I].Track <> Player[I + 1].Track) then
        begin
          Name1 := Player[I].Name;
          Name2 := Player[I + 1].Name;
          Score1 := Round(Player[I].ScoreTotalInt);
          Score2 := Round(Player[I + 1].ScoreTotalInt);

          if UTF8CompareStr(Name1, Name2) <= 0 then
            CombinedName := Format('%s & %s', [Name1, Name2])
          else
            CombinedName := Format('%s & %s', [Name2, Name1]);

          CombinedScore := (Score1 + Score2) div 2;
          if CombinedScore > 0 then
          begin
            CombinedMask := (1 shl Player[I].Track) or
                (1 shl Player[I + 1].Track);
            DataBase.AddScore(CurrentSong, Player[I].Level,
                Length(CurrentSong.Tracks), CombinedMask,
                CombinedName, CombinedScore);
            Sung := true;
          end;
        end;

        Inc(I, 2);
      end;
    end;
  end;

  if Sung then
    DataBase.WriteScore(CurrentSong);
end;

procedure TScreenSingController.AutoSendScore;
var
  SendInfo: TSendInfo;
  SendStatus: byte;
  Send: boolean;
  TotalScore: integer;
  PlayerIndex, IndexWeb, IndexUser: integer;
begin
  if CurrentSong.isDuet then
    Exit;

  for PlayerIndex := 1 to PlayersPlay do
  begin
    for IndexWeb := 0 to High(DataBase.NetworkUser) do
    begin
      for IndexUser := 0 to High(DataBase.NetworkUser[IndexWeb].Userlist) do
      begin
        Send := false;
        TotalScore := player[PlayerIndex - 1].ScoreTotalInt;

        case (player[PlayerIndex - 1].Level) of
          0: if (TotalScore >= DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoScoreEasy)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoMode = 1)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoPlayer = PlayerIndex - 1) then
                Send := true;

          1: if (TotalScore >= DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoScoreMedium)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoMode = 1)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoPlayer = PlayerIndex - 1) then
                Send := true;

          2: if (TotalScore >= DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoScoreHard)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoMode = 1)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoPlayer = PlayerIndex - 1) then
                Send := true;
        end;

        if (Send) then
        begin

          DllMan.LoadWebsite(IndexWeb);

          SendInfo.Username := DataBase.NetworkUser[IndexWeb].UserList[IndexUser].Username;
          SendInfo.Password := DataBase.NetworkUser[IndexWeb].UserList[IndexUser].Password;
          SendInfo.ScoreInt := player[PlayerIndex - 1].ScoreInt;
          SendInfo.ScoreLineInt := player[PlayerIndex - 1].ScoreLineInt;
          SendInfo.ScoreGoldenInt := player[PlayerIndex - 1].ScoreGoldenInt;
          SendInfo.MD5Song := Act_MD5Song;
          SendInfo.Level := player[PlayerIndex - 1].Level;

          SendStatus := DllMan.WebsiteSendScore(SendInfo);

          case SendStatus of
            0: ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_NO_CONNECTION'));
            2: ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_LOGIN_ERROR'));
            3: ScreenPopupInfo.ShowPopup(Language.Translate('WEBSITE_OK_SEND'));
            4: ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_ERROR_SCORE'));
            5: ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_ERROR_SCORE_DUPLICATED'));
            7: ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_ERROR_SONG'));
            WEBSITE_STATUS_NONSTANDARD_SCORE_FACTORS:
              ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_ERROR_NONSTANDARD_SCORE_FACTORS'));
          end;

       end;
      end;
    end;
  end;
end;

procedure TScreenSingController.AutoSaveScore;
var
  SendInfo: TSendInfo;
  ScoreFile: TextFile;
  EncryptText: string;
  WebName: UTF8String;
  Save: boolean;
  TotalScore: integer;
  PlayerIndex, IndexWeb, IndexUser: integer;
begin
  if CurrentSong.isDuet then
    Exit;

  for PlayerIndex := 1 to PlayersPlay do
  begin
    for IndexWeb := 0 to High(DataBase.NetworkUser) do
    begin
      for IndexUser := 0 to High(DataBase.NetworkUser[IndexWeb].Userlist) do
      begin
        Save := false;
        TotalScore := player[PlayerIndex - 1].ScoreTotalInt;

        case (player[PlayerIndex - 1].Level) of
          0: if (TotalScore >= DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoScoreEasy)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoMode = 2)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoPlayer = PlayerIndex - 1) then
                Save := true;

          1: if (TotalScore >= DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoScoreMedium)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoMode = 2)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoPlayer = PlayerIndex - 1) then
                Save := true;

          2: if (TotalScore >= DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoScoreHard)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoMode = 2)
              and (DataBase.NetworkUser[IndexWeb].UserList[IndexUser].AutoPlayer = PlayerIndex - 1) then
                Save := true;
        end;

        if (Save) then
        begin

          if not HasStandardScoreFactors then
          begin
            ScreenPopupError.ShowPopup(Language.Translate('WEBSITE_ERROR_NONSTANDARD_SCORE_FACTORS'));
            Exit;
          end;

          DllMan.LoadWebsite(IndexWeb);

          SendInfo.Username := DataBase.NetworkUser[IndexWeb].UserList[IndexUser].Username;
          SendInfo.Password := DataBase.NetworkUser[IndexWeb].UserList[IndexUser].Password;
          SendInfo.ScoreInt := player[PlayerIndex - 1].ScoreInt;
          SendInfo.ScoreLineInt := player[PlayerIndex - 1].ScoreLineInt;
          SendInfo.ScoreGoldenInt := player[PlayerIndex - 1].ScoreGoldenInt;
          SendInfo.MD5Song := Act_MD5Song;
          SendInfo.Level := player[PlayerIndex - 1].Level;

          WebName := DataBase.NetworkUser[IndexWeb].Website;
          EncryptText := DllMan.WebsiteEncryptScore(SendInfo);

          AssignFile(ScoreFile, WebScoresPath.Append(WebName + '.usc').ToNative);

          if FileExists(WebScoresPath.Append(WebName + '.usc').ToNative) then
            Append(ScoreFile)
          else
            Rewrite(ScoreFile);

          WriteLn(ScoreFile, DatetoStr(Now) + '|' + TimetoStr(Now) + '|' + EncryptText);

          Flush(ScoreFile);
          Close(ScoreFile);

          ScreenPopupInfo.ShowPopup(Language.Translate('WEBSITE_SAVE_SCORE'));

       end;
      end;
    end;
  end;
end;

end.
