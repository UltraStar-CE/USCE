{* UltraStar Deluxe - optional libmpv video playback.
 * Distributed under the GNU General Public License, version 2 or later.
 *}
unit UVideo_MPV;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

{$I switches.inc}

implementation

uses
  SysUtils,
  Math,
  ctypes,
  sdl2,
  mpv,
  UGraphic,
  UIni,
  ULog,
  UMusic,
  UPath,
  URenderer,
  UVideoPresenter,
  UVideoSync;

const
  propertyPosition = 1;
  propertyWidth = 2;
  propertyHeight = 3;
  propertyDuration = 4;
  propertyHardwareDecoder = 5;
  requestLoad = 100;
  requestPause = 101;
  requestSpeed = 102;
  requestSeek = 103;
  requestLoop = 104;
  openTimeout = 5.0;
  seekTimeout = 5.0;

type
{$IFDEF Linux}
  {$PACKRECORDS C}
  { SDL2's public SysWMinfo ABI reserves 64 bytes for native window handles.
    The bundled Pascal SDL headers predate its Wayland declaration. Both X11
    and Wayland place their display pointer first in this union. }
  TMpvWindowInfo = record
    version: TSDL_version;
    subsystem: cint;
    case integer of
      0: (display: Pointer);
      1: (reserved: array[0..63] of byte);
  end;
  {$PACKRECORDS DEFAULT}
{$ENDIF}

  TVideo_MPV = class(TVideoPresenter)
    private
      fHandle: Pmpv_handle;
      fContext: Pmpv_render_context;
      fTarget: TRenderTarget;
      fSync: TExternalVideoSync;
      fLibraryLoaded: boolean;
      fOpened, fFileLoaded, fFailed: boolean;
      fPlaybackStarted: boolean;
      fPaused, fStopped, fLoop: boolean;
      fUpdatePending: longint;
      fRenderPending: boolean;
      fVideoWidth, fVideoHeight: integer;
      fDuration, fPosition, fPlaybackPosition: double;
      fHavePosition: boolean;
      fHardwareDecoder: string;
      fLoggedDecoder: boolean;

      fDesiredPause, fAppliedPause, fSentPause, fPausePending: boolean;
      fDesiredSpeed, fAppliedSpeed, fSentSpeed: double;
      fSpeedPending: boolean;
      fAppliedLoop, fSentLoop, fLoopPending: boolean;
      fSeekWanted, fSeekPending, fSeeking, fSeekNotified: boolean;
      fSeekPosition, fSentSeekPosition, fSeekStarted: double;

      procedure Fail(const Message: string);
      function SetOption(const Name, Value: AnsiString): boolean;
      function Command(Id: QWord; const Args: array of AnsiString): boolean;
      function Observe(Id: QWord; const Name: AnsiString; Format: cint): boolean;
      function CreatePlayer(): boolean;
      function CreateContext(): boolean;
      function EnsureTarget(): boolean;
      procedure ReadProperty(Event: Pmpv_event);
      procedure PumpEvents;
      procedure RenderFrame;
      procedure ApplyControl;
      procedure QueueSeek(Position: double);
    public
      constructor Create;
      destructor Destroy; override;
      function Open(const FileName: IPath): boolean; override;
      procedure Close; override;
      procedure Play; override;
      procedure Pause; override;
      procedure Stop; override;
      procedure SetLoop(Enable: boolean); override;
      function GetLoop(): boolean; override;
      procedure SetPosition(Time: real); override;
      function GetPosition: real; override;
      procedure GetFrame(Time: Extended); override;
      procedure Draw; override;
  end;

  TVideoPlayback_MPV = class(TInterfacedObject, IVideoPlayback)
    private
      fInitialized: boolean;
    public
      function GetName: string;
      function Init(): boolean;
      function Finalize(): boolean;
      function Open(const FileName: IPath): IVideo;
  end;

function MonotonicTime: double;
begin
  Result := SDL_GetPerformanceCounter() / SDL_GetPerformanceFrequency();
end;

function MpvError(Code: cint): string;
begin
  Result := string(mpv_error_string(Code));
end;

function MpvProcAddress(Context: Pointer; Name: PAnsiChar): Pointer; cdecl;
begin
  Result := SDL_GL_GetProcAddress(Name);
end;

procedure MpvUpdate(Context: Pointer); cdecl;
begin
  { mpv invokes this from foreign threads. No GL, client calls or logging. }
  InterlockedExchange(PLongint(Context)^, 1);
end;

function TVideoPlayback_MPV.GetName: string;
begin
  Result := 'MPV_Video';
end;

function TVideoPlayback_MPV.Init(): boolean;
begin
  if fInitialized then
    Exit(true);
  Result := (Ini.VideoBackend = 'mpv');
  if not Result then
    Exit;
  fInitialized := LoadMpv();
  Result := fInitialized;
  if not Result then
    Log.LogWarn(MpvLoadError() + '; using the next video backend', 'TVideoPlayback_MPV.Init');
end;

function TVideoPlayback_MPV.Finalize(): boolean;
begin
  if fInitialized then
    UnloadMpv();
  fInitialized := false;
  Result := true;
end;

function TVideoPlayback_MPV.Open(const FileName: IPath): IVideo;
var
  video: TVideo_MPV;
begin
  Result := nil;
  video := TVideo_MPV.Create;
  if video.Open(FileName) then
    Result := video
  else
  begin
    video.Free;
    Result := OpenVideoFallback(FileName, Self as IVideoPlayback);
  end;
end;

constructor TVideo_MPV.Create;
begin
  inherited Create;
  fSync := TExternalVideoSync.Create;
end;

destructor TVideo_MPV.Destroy;
begin
  Close;
  fSync.Free;
  inherited Destroy;
end;

procedure TVideo_MPV.Fail(const Message: string);
begin
  if not fFailed then
    Log.LogError(Message, 'TVideo_MPV');
  fFailed := true;
end;

function TVideo_MPV.SetOption(const Name, Value: AnsiString): boolean;
var
  code: cint;
begin
  code := mpv_set_option_string(fHandle, PAnsiChar(Name), PAnsiChar(Value));
  Result := code >= 0;
  if not Result then
    Fail('Cannot set ' + Name + ': ' + MpvError(code));
end;

function TVideo_MPV.Command(Id: QWord; const Args: array of AnsiString): boolean;
var
  pointers: array of PAnsiChar;
  i: integer;
  code: cint;
begin
  SetLength(pointers, Length(Args) + 1);
  for i := 0 to High(Args) do
    pointers[i] := PAnsiChar(Args[i]);
  pointers[Length(Args)] := nil;
  code := mpv_command_async(fHandle, Id, @pointers[0]);
  Result := code >= 0;
  if not Result then
    Fail('Cannot queue libmpv command: ' + MpvError(code));
end;

function TVideo_MPV.Observe(Id: QWord; const Name: AnsiString; Format: cint): boolean;
var
  code: cint;
begin
  code := mpv_observe_property(fHandle, Id, PAnsiChar(Name), Format);
  Result := code >= 0;
  if not Result then
    Fail('Cannot observe ' + Name + ': ' + MpvError(code));
end;

function TVideo_MPV.CreatePlayer(): boolean;
var
  code: cint;
begin
  Result := false;
  fHandle := mpv_create();
  if fHandle = nil then
  begin
    Fail('Cannot create libmpv player');
    Exit;
  end;

  { Do not inherit mpv.conf, scripts, audio, subtitles or input bindings. USDX
    owns those features, and its audio clock remains the playback master.
    Bilinear chroma upsampling avoids black paused startup
    frames seen with mpv's default multipass chroma scaler on Mesa. }
  if not (SetOption('config', 'no') and
          SetOption('terminal', 'no') and
          SetOption('vo', 'libmpv') and
          SetOption('cscale', 'bilinear') and
          SetOption('audio', 'no') and
          SetOption('sid', 'no') and
          SetOption('sub-auto', 'no') and
          SetOption('load-scripts', 'no') and
          SetOption('osc', 'no') and
          SetOption('osd-level', '0') and
          SetOption('input-default-bindings', 'no') and
          SetOption('input-vo-keyboard', 'no') and
          SetOption('pause', 'yes') and
          SetOption('keep-open', 'yes') and
          SetOption('keep-open-pause', 'no') and
          SetOption('video-timing-offset', '0') and
          SetOption('hwdec', AnsiString(Ini.VideoHardwareDecoding))) then
    Exit;

  code := mpv_initialize(fHandle);
  if code < 0 then
  begin
    Fail('Cannot initialize libmpv: ' + MpvError(code));
    Exit;
  end;
  mpv_request_log_messages(fHandle, 'warn');

  Result := Observe(propertyPosition, 'time-pos', MPV_FORMAT_DOUBLE) and
            Observe(propertyWidth, 'dwidth', MPV_FORMAT_INT64) and
            Observe(propertyHeight, 'dheight', MPV_FORMAT_INT64) and
            Observe(propertyDuration, 'duration', MPV_FORMAT_DOUBLE) and
            Observe(propertyHardwareDecoder, 'hwdec-current', MPV_FORMAT_STRING);
end;

function TVideo_MPV.CreateContext(): boolean;
var
  init: Tmpv_opengl_init_params;
  params: array[0..3] of Tmpv_render_param;
  index: integer;
  code: cint;
{$IFDEF Linux}
  windowInfo: TMpvWindowInfo;
{$ENDIF}
begin
  Result := false;
  { The first frame must be rendered before mpv publishes display dimensions.
    Start with the window's drawable area, then use the video's dimensions. }
  fTarget := Renderer.CreateRenderTarget(
    Min(Max(16, ScreenWPerScreen), Renderer.MaxTextureSize),
    Min(Max(16, ScreenH), Renderer.MaxTextureSize));
  if (fTarget = nil) or (fTarget.NativeAPI <> 'opengl') then
  begin
    Fail('The renderer does not support libmpv render targets');
    Exit;
  end;

  FillChar(params, SizeOf(params), 0);
  FillChar(init, SizeOf(init), 0);
  init.get_proc_address := MpvProcAddress;
  init.get_proc_address_ctx := nil;
  params[0].param_type := MPV_RENDER_PARAM_API_TYPE;
  params[0].data := PAnsiChar('opengl');
  params[1].param_type := MPV_RENDER_PARAM_OPENGL_INIT_PARAMS;
  params[1].data := @init;
  index := 2;

{$IFDEF Linux}
  FillChar(windowInfo, SizeOf(windowInfo), 0);
  SDL_VERSION(windowInfo.version);
  if (Screen <> nil) and
    (SDL_GetWindowWMInfo(Screen, PSDL_SysWMinfo(@windowInfo)) = SDL_TRUE) then
  begin
    case windowInfo.subsystem of
      Ord(SDL_SYSWM_X11):
      begin
        params[index].param_type := MPV_RENDER_PARAM_X11_DISPLAY;
        params[index].data := windowInfo.display;
        Inc(index);
      end;
      Ord(SDL_SYSWM_WAYLAND):
      begin
        params[index].param_type := MPV_RENDER_PARAM_WL_DISPLAY;
        params[index].data := windowInfo.display;
        Inc(index);
      end;
    end;
  end;
{$ENDIF}
  params[index].param_type := MPV_RENDER_PARAM_INVALID;
  { Advanced control is intentionally left disabled. The regular render API
    supports hardware decoding and avoids requiring decoder allocations while
    USDX is not drawing this video (for example during a screen transition). }
  fTarget.BeginRender;
  try
    code := mpv_render_context_create(fContext, fHandle, @params[0]);
  finally
    fTarget.EndRender;
  end;
  if code < 0 then
  begin
    Fail('Cannot initialize libmpv rendering: ' + MpvError(code));
    Exit;
  end;
  mpv_render_context_set_update_callback(fContext, MpvUpdate, @fUpdatePending);
  Result := true;
end;

function TVideo_MPV.EnsureTarget(): boolean;
var
  target: TRenderTarget;
begin
  Result := false;
  if (fVideoWidth <= 0) or (fVideoHeight <= 0) then
    Exit;
  if (fTarget.Width <> fVideoWidth) or (fTarget.Height <> fVideoHeight) then
  begin
    target := Renderer.CreateRenderTarget(fVideoWidth, fVideoHeight);
    if target = nil then
    begin
      Fail('Cannot create libmpv video texture');
      Exit;
    end;
    if fFrameTex <> nil then
    begin
      target.Texture.Reflection := fFrameTex.Reflection;
      target.Texture.ReflectionSpacing := fFrameTex.ReflectionSpacing;
      target.Texture.ReflectionHeight := fFrameTex.ReflectionHeight;
      target.Texture.ReflectionAlphaDiff := fFrameTex.ReflectionAlphaDiff;
      target.Texture.ReflectionTexY1 := fFrameTex.ReflectionTexY1;
      target.Texture.ReflectionTexY2 := fFrameTex.ReflectionTexY2;
    end;
    fFrameTex := nil;
    fTarget.Free;
    fTarget := target;
    fFrameTexValid := false;
    { mpv may have rendered the paused first frame into the bootstrap target
      before publishing display dimensions. Redraw its cached frame here. }
    fRenderPending := true;
  end;
  if fFrameTex = nil then
    fRenderPending := true;
  fFrameTex := fTarget.Texture;
  fTexWidth := fTarget.Width;
  fTexHeight := fTarget.Height;
  fScaledWidth := fTexWidth;
  fScaledHeight := fTexHeight;
  fAspect := fVideoWidth / fVideoHeight;
  Result := true;
end;

procedure TVideo_MPV.ReadProperty(Event: Pmpv_event);
var
  value: Pmpv_event_property;
  size: Int64;
  hardware: string;
begin
  value := Event^.data;
  if (value = nil) or (value^.data = nil) or (value^.format = MPV_FORMAT_NONE) then
    Exit;
  case Event^.reply_userdata of
    propertyPosition:
      if value^.format = MPV_FORMAT_DOUBLE then
      begin
        fPlaybackPosition := PDouble(value^.data)^;
        fHavePosition := not IsNan(fPlaybackPosition) and not IsInfinite(fPlaybackPosition);
      end;
    propertyWidth, propertyHeight:
      if value^.format = MPV_FORMAT_INT64 then
      begin
        size := PInt64(value^.data)^;
        if (size > 0) and (size <= High(integer)) then
        begin
          if Event^.reply_userdata = propertyWidth then
            fVideoWidth := size
          else
            fVideoHeight := size;
        end;
      end;
    propertyDuration:
      if value^.format = MPV_FORMAT_DOUBLE then
      begin
        fDuration := PDouble(value^.data)^;
        if IsNan(fDuration) or IsInfinite(fDuration) or (fDuration < 0) then
          fDuration := 0;
      end;
    propertyHardwareDecoder:
      if (value^.format = MPV_FORMAT_STRING) and (mpv.PPAnsiChar(value^.data)^ <> nil) then
      begin
        hardware := string(mpv.PPAnsiChar(value^.data)^);
        if hardware <> fHardwareDecoder then
        begin
          fHardwareDecoder := hardware;
          fLoggedDecoder := false;
        end;
      end;
  end;
end;

procedure TVideo_MPV.PumpEvents;
var
  event: Pmpv_event;
  message: Pmpv_event_log_message;
  ended: Pmpv_event_end_file;
begin
  if fHandle = nil then
    Exit;
  repeat
    { Only zero-timeout polling is safe on the render thread. All event-owned
      strings/data are consumed before polling the next event. }
    event := mpv_wait_event(fHandle, 0);
    case event^.event_id of
      MPV_EVENT_FILE_LOADED:
        fFileLoaded := true;
      MPV_EVENT_PROPERTY_CHANGE, MPV_EVENT_GET_PROPERTY_REPLY:
        ReadProperty(event);
      MPV_EVENT_SEEK:
        if fSeeking then
          fSeekNotified := true;
      MPV_EVENT_PLAYBACK_RESTART:
      begin
        fPlaybackStarted := true;
        { Redraw after startup or a seek, including a frame that the VO moved
          into its cache after its presentation timeout. }
        fRenderPending := true;
        if fSeekNotified then
          fSeeking := false;
      end;
      MPV_EVENT_COMMAND_REPLY:
      begin
        if event^.error < 0 then
          Fail('libmpv command failed: ' + MpvError(event^.error));
        case event^.reply_userdata of
          requestSeek: fSeekPending := false;
          requestLoop:
          begin
            fLoopPending := false;
            fAppliedLoop := fSentLoop;
          end;
        end;
      end;
      MPV_EVENT_SET_PROPERTY_REPLY:
      begin
        if event^.error < 0 then
          Fail('libmpv playback control failed: ' + MpvError(event^.error));
        case event^.reply_userdata of
          requestPause:
          begin
            fPausePending := false;
            fAppliedPause := fSentPause;
          end;
          requestSpeed:
          begin
            fSpeedPending := false;
            fAppliedSpeed := fSentSpeed;
          end;
        end;
      end;
      MPV_EVENT_END_FILE:
      begin
        ended := event^.data;
        if (ended <> nil) and (ended^.reason = MPV_END_FILE_REASON_ERROR) then
          Fail('libmpv could not decode the video: ' + MpvError(ended^.error))
        else if not fFileLoaded then
          Fail('libmpv could not load a video track');
      end;
      MPV_EVENT_SHUTDOWN:
        Fail('libmpv shut down unexpectedly');
      MPV_EVENT_QUEUE_OVERFLOW:
        Fail('libmpv event queue overflowed');
      MPV_EVENT_LOG_MESSAGE:
      begin
        message := event^.data;
        if (message <> nil) and (message^.text <> nil) then
          Log.LogWarn(Trim(string(message^.text)), 'libmpv');
      end;
    end;
  until event^.event_id = MPV_EVENT_NONE;
end;

procedure TVideo_MPV.RenderFrame;
var
  flags: QWord;
  fbo: Tmpv_opengl_fbo;
  params: array[0..3] of Tmpv_render_param;
  flipY, blockForTime, code: cint;
  targetReady, updatePending: boolean;
begin
  if (fContext = nil) or fFailed then
    Exit;
  targetReady := EnsureTarget();
  if fFailed then
    Exit;
  updatePending := InterlockedExchange(fUpdatePending, 0) <> 0;
  if not updatePending and
     not fRenderPending and fFrameTexValid then
    Exit;

  fTarget.BeginRender;
  try
    flags := mpv_render_context_update(fContext);
    { With regular control mpv can move a timed-out queued frame into its
      current-frame cache. Its earlier callback still requires a redraw even
      though update() now reports no next frame. }
    fRenderPending := fRenderPending or updatePending or
      ((flags and MPV_RENDER_UPDATE_FRAME) <> 0);
    if not fRenderPending then
      Exit;

    fbo.fbo := fTarget.NativeHandle;
    fbo.w := fTarget.Width;
    fbo.h := fTarget.Height;
    fbo.internal_format := 0;
    flipY := 0;
    blockForTime := 0;
    FillChar(params, SizeOf(params), 0);
    params[0].param_type := MPV_RENDER_PARAM_OPENGL_FBO;
    params[0].data := @fbo;
    params[1].param_type := MPV_RENDER_PARAM_FLIP_Y;
    params[1].data := @flipY;
    params[2].param_type := MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME;
    params[2].data := @blockForTime;
    code := mpv_render_context_render(fContext, @params[0]);
    fRenderPending := false;
    if code < 0 then
      Fail('libmpv rendering failed: ' + MpvError(code))
    else
      { A successful render may draw only an initialization background.
        PLAYBACK_RESTART confirms the first video frame and forces a redraw. }
      fFrameTexValid := targetReady and fPlaybackStarted;
  finally
    fTarget.EndRender;
  end;

  if fFrameTexValid and not fLoggedDecoder and (fHardwareDecoder <> '') then
  begin
    Log.LogInfo('Hardware decoder: ' + fHardwareDecoder, 'TVideo_MPV');
    fLoggedDecoder := true;
  end;
end;

procedure TVideo_MPV.QueueSeek(Position: double);
begin
  fSeekPosition := Position;
  fSeekWanted := true;
end;

procedure TVideo_MPV.ApplyControl;
var
  flag, code: cint;
  format: TFormatSettings;
begin
  if (fHandle = nil) or fFailed then
    Exit;

  { At most one outstanding request for each property. Its acknowledgement
    is processed before submitting a newer value, preserving rapid toggles. }
  if not fPausePending and (fDesiredPause <> fAppliedPause) then
  begin
    fSentPause := fDesiredPause;
    flag := Ord(fSentPause);
    code := mpv_set_property_async(fHandle, requestPause, 'pause', MPV_FORMAT_FLAG, @flag);
    if code < 0 then
      Fail('Cannot change libmpv pause state: ' + MpvError(code))
    else
      fPausePending := true;
  end;
  if not fSpeedPending and (Abs(fDesiredSpeed - fAppliedSpeed) > 0.001) then
  begin
    fSentSpeed := fDesiredSpeed;
    code := mpv_set_property_async(fHandle, requestSpeed, 'speed', MPV_FORMAT_DOUBLE, @fSentSpeed);
    if code < 0 then
      Fail('Cannot change libmpv speed: ' + MpvError(code))
    else
      fSpeedPending := true;
  end;
  if not fLoopPending and (fLoop <> fAppliedLoop) then
  begin
    fSentLoop := fLoop;
    if fSentLoop then
      fLoopPending := Command(requestLoop, ['set', 'loop-file', 'inf'])
    else
      fLoopPending := Command(requestLoop, ['set', 'loop-file', 'no']);
  end;
  if fSeekWanted and not fSeekPending and not fSeeking then
  begin
    format := DefaultFormatSettings;
    format.DecimalSeparator := '.';
    fSentSeekPosition := fSeekPosition;
    fSeekPending := Command(requestSeek, ['seek',
      FloatToStrF(fSentSeekPosition, ffFixed, 18, 6, format), 'absolute+exact']);
    fSeeking := fSeekPending;
    fSeekNotified := false;
    fSeekStarted := MonotonicTime;
    fSeekWanted := false;
    fFrameTexValid := false;
  end;
end;

function TVideo_MPV.Open(const FileName: IPath): boolean;
var
  deadline: double;
  filenameUTF8: AnsiString;
begin
  Close;
  ResetPresentation;
  Result := false;
  fLibraryLoaded := LoadMpv();
  if not fLibraryLoaded then
    Exit;

  try
    if not CreatePlayer() or not CreateContext() then
      Exit;
    filenameUTF8 := FileName.GetAbsolutePath().ToUTF8();
    if not Command(requestLoad, ['loadfile', filenameUTF8, 'replace']) then
      Exit;

    deadline := MonotonicTime + openTimeout;
    repeat
      PumpEvents;
      RenderFrame;
      if fFailed then
        Exit;
      if fFileLoaded and fPlaybackStarted and fFrameTexValid then
      begin
        fOpened := true;
        Log.LogInfo('Using libmpv video (' + IntToStr(fVideoWidth) + 'x' +
          IntToStr(fVideoHeight) + ') for ' + FileName.ToUTF8(), 'TVideo_MPV');
        Exit(true);
      end;
      SDL_Delay(1);
    until MonotonicTime >= deadline;
    Fail('Timed out opening video with libmpv');
  finally
    if not fOpened then
      Close;
  end;
end;

procedure TVideo_MPV.Close;
begin
  if fContext <> nil then
  begin
    mpv_render_context_set_update_callback(fContext, nil, nil);
    fTarget.BeginRender;
    try
      mpv_render_context_free(fContext);
      fContext := nil;
    finally
      fTarget.EndRender;
    end;
  end;
  fFrameTex := nil;
  FreeAndNil(fTarget);
  if fHandle <> nil then
  begin
    mpv_terminate_destroy(fHandle);
    fHandle := nil;
  end;
  if fLibraryLoaded then
    UnloadMpv;
  fLibraryLoaded := false;
  fOpened := false;
  fFileLoaded := false;
  fPlaybackStarted := false;
  fFailed := false;
  fPaused := false;
  fStopped := false;
  fLoop := false;
  fUpdatePending := 0;
  fRenderPending := false;
  fFrameTexValid := false;
  fVideoWidth := 0;
  fVideoHeight := 0;
  fDuration := 0;
  fPosition := 0;
  fPlaybackPosition := 0;
  fHavePosition := false;
  fHardwareDecoder := '';
  fLoggedDecoder := false;
  fDesiredPause := true;
  fAppliedPause := true;
  fPausePending := false;
  fDesiredSpeed := 1;
  fAppliedSpeed := 1;
  fSpeedPending := false;
  fAppliedLoop := false;
  fLoopPending := false;
  fSeekWanted := false;
  fSeekPending := false;
  fSeeking := false;
  fSeekNotified := false;
  if fSync <> nil then
    fSync.Reset;
end;

procedure TVideo_MPV.Play;
begin
  fPaused := false;
  fStopped := false;
  fSync.Reset;
end;

procedure TVideo_MPV.Pause;
begin
  fPaused := not fPaused;
  fSync.Reset;
  if fPaused then
  begin
    fDesiredPause := true;
    fDesiredSpeed := 1;
    ApplyControl;
  end;
end;

procedure TVideo_MPV.Stop;
begin
  fStopped := true;
  fDesiredPause := true;
  fDesiredSpeed := 1;
  ApplyControl;
end;

procedure TVideo_MPV.SetLoop(Enable: boolean);
begin
  fLoop := Enable;
  fSync.Reset;
  ApplyControl;
end;

function TVideo_MPV.GetLoop(): boolean;
begin
  Result := fLoop;
end;

procedure TVideo_MPV.SetPosition(Time: real);
begin
  if IsNan(Time) or IsInfinite(Time) then
    Exit;
  fPosition := VideoLoopPosition(Time, fDuration, fLoop);
  fSync.Reset;
  if fOpened then
  begin
    QueueSeek(fPosition);
    ApplyControl;
  end;
end;

function TVideo_MPV.GetPosition: real;
begin
  Result := fPosition;
end;

procedure TVideo_MPV.GetFrame(Time: Extended);
var
  now: double;
  decision: TVideoSyncDecision;
begin
  if not fOpened or fFailed then
    Exit;
  PumpEvents;
  now := MonotonicTime;
  if (fSeekPending or fSeeking) and (now - fSeekStarted >= seekTimeout) then
    Fail('Timed out seeking libmpv video');

  if not IsNan(Time) and not IsInfinite(Time) then
  begin
    decision := fSync.Update(Time, fPlaybackPosition, now, fDuration,
      fHavePosition and not fSeekPending and not fSeeking and not fSeekWanted,
      fLoop, fPaused or fStopped);
    fPosition := decision.Position;
    fDesiredPause := decision.Paused;
    fDesiredSpeed := decision.Speed;
    if decision.Seek then
      QueueSeek(decision.Position);
    ApplyControl;
  end;
  { Even a paused player must render its initial frame and seek results. }
  RenderFrame;
end;

procedure TVideo_MPV.Draw;
begin
  if fFrameTexValid and not fSeeking and not fSeekPending then
    inherited Draw;
end;

initialization
  MediaManager.Insert(0, TVideoPlayback_MPV.Create);

end.
