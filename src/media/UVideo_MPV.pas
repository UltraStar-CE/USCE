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
  Classes,
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
  propertyEndReached = 6;
  requestLoad = 100;
  requestPause = 101;
  requestSpeed = 102;
  requestSeek = 103;
  requestLoop = 104;
  requestHwdec = 105;
  requestCodec = 106;
  requestPark = 107;
  requestDecoder = 108;
  openTimeout = 5.0;
  parkTimeout = 2.0;
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

  TMpvArgs = array of PAnsiChar;

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
      fEndReached: boolean;
      fHardwareDecoder: string;
      fLoggedDecoder: boolean;
      fCodec: string;
      fDecoderSwitchSent, fDecoderSwitchReplied, fDecoderProbed: boolean;
      fInitialRead: boolean;

      fDesiredPause, fAppliedPause, fSentPause, fPausePending: boolean;
      fDesiredSpeed, fAppliedSpeed, fSentSpeed: double;
      fSpeedPending: boolean;
      fAppliedLoop, fSentLoop, fLoopPending: boolean;
      fSeekWanted, fSeekPending, fSeeking, fSeekNotified: boolean;
      fSeekPosition, fSentSeekPosition, fSeekStarted: double;

      procedure Fail(const Message: string);
      function SetOption(const Name, Value: AnsiString): boolean;
      function SetOptionIfKnown(const Name, Value: AnsiString): boolean;
      function Command(Id: QWord; const Args: array of AnsiString): boolean;
      procedure ReadInitialProperties;
      function Observe(Id: QWord; const Name: AnsiString; Format: cint): boolean;
      function CreatePlayer(): boolean;
      function CreateContext(): boolean;
      function AdoptParkedPlayer(): boolean;
      function ParkPlayer(): boolean;
      procedure RequestHardwareDecoding;
      procedure SelectHardwareDecoder;
      procedure RememberDecoder(Decoder: string);
      function EnsureTarget(): boolean;
      procedure ReadProperty(Event: Pmpv_event);
      procedure PumpEvents;
      procedure RenderFrame;
      procedure ApplyControl;
      procedure QueueSeek(Position: double);
    public
      constructor Create;
      destructor Destroy; override;
      function Open(const FileName: IPath; const Media: TBytes = nil): boolean; override;
      procedure Close; override;
      procedure Play; override;
      procedure Pause; override;
      procedure Stop; override;
      procedure SetLoop(Enable: boolean); override;
      function GetLoop(): boolean; override;
      procedure SetPosition(Time: real); override;
      function GetPosition: real; override;
      procedure GetFrame(Time: Extended); override;
      function Finished: boolean; override;
      procedure Draw; override;
  end;

  TVideoPlayback_MPV = class(TInterfacedObject, IVideoPlayback)
    private
      fInitialized: boolean;
      fFallback: IVideoPlayback;
      fLibraryLoaded, fLibraryMissing: boolean;
      function LibraryLoaded(): boolean;
      function OpenFallback(const FileName: IPath; const Media: TBytes): IVideo;
    public
      function GetName: string;
      function Init(): boolean;
      function Finalize(): boolean;
      function Open(const FileName: IPath; const Media: TBytes = nil): IVideo;
  end;

var
  { One idle player outlives Close so the next Open reuses it instead of
    creating a player and a render context. Until the first frame is in the
    texture, a new player took 554 to 792 ms and a reused one 26 to 48 ms on
    Windows with an RTX 2080 SUPER, where most of the difference is libmpv
    loading the hardware decoder interfaces with the render context. With
    Intel UHD Graphics it was 248 to 339 ms against 27 to 58 ms. The smoke
    test reports both times. }
  parkedHandle: Pmpv_handle;
  parkedContext: Pmpv_render_context;
  parkedTarget: TRenderTarget;
  { hwdec-current per video codec for this session. mpv probes every decoder
    on every open; a codec the GPU cannot decode spent 10 s per open. }
  rememberedDecoders: TStringList;

procedure DestroyParkedPlayer;
begin
  if parkedHandle = nil then
    Exit;
  parkedTarget.BeginRender;
  try
    mpv_render_context_free(parkedContext);
  finally
    parkedTarget.EndRender;
  end;
  FreeAndNil(parkedTarget);
  parkedContext := nil;
  mpv_terminate_destroy(parkedHandle);
  parkedHandle := nil;
  UnloadMpv;
end;

function MonotonicTime: double;
begin
  Result := SDL_GetPerformanceCounter() / SDL_GetPerformanceFrequency();
end;

function MpvError(Code: cint): string;
begin
  Result := string(mpv_error_string(Code));
end;

{ The nil-terminated argument list of mpv_command_async.
  The entries point into Args, so Args must outlive every use of the list. }
function MpvArgs(const Args: array of AnsiString): TMpvArgs;
var
  i: integer;
begin
  SetLength(Result, Length(Args) + 1);
  for i := 0 to High(Args) do
    Result[i] := PAnsiChar(Args[i]);
  Result[Length(Args)] := nil;
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

{ This provider comes first, so InitializeVideo selects it whenever a video can
  be played at all, and it decides per video in Open. }
function TVideoPlayback_MPV.Init(): boolean;
var
  i: integer;
  provider: IVideoPlayback;
  foundSelf: boolean;
begin
  if not fInitialized then
  begin
    { The fallback is the next video provider that is not a visualization,
      which is FFmpeg: the dummy provider and the visualizers implement
      IVideoVisualization. }
    foundSelf := false;
    for i := 0 to MediaManager.Count - 1 do
      if Supports(MediaManager[i], IVideoPlayback, provider) then
      begin
        if provider = Self as IVideoPlayback then
          foundSelf := true
        else if foundSelf and not Supports(provider, IVideoVisualization) then
        begin
          if provider.Init() then
            fFallback := provider;
          Break;
        end;
      end;
    fInitialized := true;
  end;
  Result := (fFallback <> nil) or LibraryLoaded();
end;

function TVideoPlayback_MPV.Finalize(): boolean;
begin
  DestroyParkedPlayer;
  fFallback := nil;
  fInitialized := false;
  Result := true;
end;

{ libmpv is loaded when a video first needs it and stays loaded until the
  process ends: it registers libavdevice's devices in libavformat's
  process-wide list, so unloading it would leave FFmpeg's next open reading
  freed memory. A missing library is reported once and not retried. }
function TVideoPlayback_MPV.LibraryLoaded(): boolean;
begin
  if not fLibraryLoaded and not fLibraryMissing then
  begin
    fLibraryLoaded := LoadMpv();
    fLibraryMissing := not fLibraryLoaded;
    if fLibraryMissing then
      Log.LogWarn(MpvLoadError() + '; FFmpeg plays all videos', 'TVideoPlayback_MPV');
  end;
  Result := fLibraryLoaded;
end;

function TVideoPlayback_MPV.OpenFallback(const FileName: IPath; const Media: TBytes): IVideo;
begin
  Result := nil;
  if fFallback <> nil then
    Result := fFallback.Open(FileName, Media);
end;

{ The policy for which backend plays a video, read at every open:
  1. Song-select previews arrive as snapshots in memory so that their files
     stay replaceable while they play (USCE #366). libmpv reads files only,
     so FFmpeg decodes every snapshot. This is the rule, not a failure.
  2. With FFmpeg configured, FFmpeg plays the video.
  3. Without a loadable libmpv, FFmpeg plays the video.
  4. Otherwise libmpv opens the file, and FFmpeg takes over when it cannot.
  Once libmpv has opened a video it keeps it. A later failure ends that video:
  Finished is true and the last frame stays until the caller drops the video.
  There is no switch to FFmpeg in mid-stream. }
function TVideoPlayback_MPV.Open(const FileName: IPath; const Media: TBytes = nil): IVideo;
var
  video: TVideo_MPV;
begin
  if (Media <> nil) or (Ini.VideoBackend <> 'mpv') or not LibraryLoaded() then
    Exit(OpenFallback(FileName, Media));
  video := TVideo_MPV.Create;
  if video.Open(FileName) then
    Result := video
  else
  begin
    video.Free;
    Result := OpenFallback(FileName, nil);
    if Result <> nil then
      Log.LogInfo('Using fallback ' + fFallback.GetName, 'VideoPlayback');
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

{ Options that only exist in libmpv builds with the matching feature. }
function TVideo_MPV.SetOptionIfKnown(const Name, Value: AnsiString): boolean;
var
  code: cint;
begin
  code := mpv_set_option_string(fHandle, PAnsiChar(Name), PAnsiChar(Value));
  Result := (code >= 0) or (code = MPV_ERROR_OPTION_NOT_FOUND);
  if not Result then
    Fail('Cannot set ' + Name + ': ' + MpvError(code));
end;

function TVideo_MPV.Command(Id: QWord; const Args: array of AnsiString): boolean;
var
  pointers: TMpvArgs;
  code: cint;
begin
  pointers := MpvArgs(Args);
  code := mpv_command_async(fHandle, Id, @pointers[0]);
  Result := code >= 0;
  if not Result then
    Fail('Cannot queue libmpv command: ' + MpvError(code));
end;

{ A reused player sends no change event for a value equal to the previous
  file's, so the first values are asked for once playback has started. They
  arrive as replies carrying the observers' ids, which ReadProperty handles.
  A synchronous read would wait for mpv's core, and after the first frame
  the core can be waiting up to 200 ms for this thread to render. }
procedure TVideo_MPV.ReadInitialProperties;
begin
  fInitialRead := true;
  mpv_get_property_async(fHandle, propertyWidth, 'dwidth', MPV_FORMAT_INT64);
  mpv_get_property_async(fHandle, propertyHeight, 'dheight', MPV_FORMAT_INT64);
  mpv_get_property_async(fHandle, propertyDuration, 'duration', MPV_FORMAT_DOUBLE);
  mpv_get_property_async(fHandle, propertyHardwareDecoder, 'hwdec-current', MPV_FORMAT_STRING);
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
    frames seen with mpv's default multipass chroma scaler on Mesa.
    Every file opens with software decoding; the hardware decoder is selected
    after the first frame, so a decoder probe never blocks the open. }
  if not (SetOption('config', 'no') and
          SetOption('terminal', 'no') and
          SetOption('idle', 'yes') and
          SetOption('vo', 'libmpv') and
          SetOption('cscale', 'bilinear') and
          SetOption('audio', 'no') and
          SetOption('sid', 'no') and
          SetOption('sub-auto', 'no') and
          SetOptionIfKnown('load-scripts', 'no') and
          SetOptionIfKnown('osc', 'no') and
          SetOption('osd-level', '0') and
          SetOption('input-default-bindings', 'no') and
          SetOption('input-vo-keyboard', 'no') and
          SetOption('pause', 'yes') and
          SetOption('keep-open', 'yes') and
          SetOption('keep-open-pause', 'no') and
          SetOption('video-timing-offset', '0') and
          SetOption('hwdec', 'no')) then
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
            Observe(propertyHardwareDecoder, 'hwdec-current', MPV_FORMAT_STRING) and
            Observe(propertyEndReached, 'eof-reached', MPV_FORMAT_FLAG);
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

function TVideo_MPV.AdoptParkedPlayer(): boolean;
begin
  Result := parkedHandle <> nil;
  if not Result then
    Exit;
  fHandle := parkedHandle;
  fContext := parkedContext;
  fTarget := parkedTarget;
  parkedHandle := nil;
  parkedContext := nil;
  parkedTarget := nil;
  { The parked player kept its LoadMpv reference. }
  fLibraryLoaded := true;
  mpv_render_context_set_update_callback(fContext, MpvUpdate, @fUpdatePending);
  fUpdatePending := 1;
  Log.LogInfo('Reusing libmpv player', 'TVideo_MPV');
end;

function TVideo_MPV.ParkPlayer(): boolean;
const
  parkCommands = 5; // the commands queued below
var
  event: Pmpv_event;
  deadline: double;
  replies: integer;
  ended, refused: boolean;
begin
  Result := false;
  if (parkedHandle <> nil) or fFailed or not fOpened or
     (fHandle = nil) or (fContext = nil) or (fTarget = nil) then
    Exit;
  { Queued, not synchronous. A synchronous call waits for mpv's core, and the
    core can itself wait up to 200 ms for this thread to render a frame the
    video output has queued. The loop keeps rendering until all replies and
    the END_FILE of stop are in: stop unloads the file asynchronously, and
    its END_FILE must not reach the next video, which would read it as a
    failed load. }
  if not (Command(requestPark, ['stop']) and
          Command(requestPark, ['set', 'pause', 'yes']) and
          Command(requestPark, ['set', 'speed', '1']) and
          Command(requestPark, ['set', 'loop-file', 'no']) and
          Command(requestPark, ['set', 'hwdec', 'no'])) then
    Exit;
  replies := 0;
  ended := false;
  refused := false;
  deadline := MonotonicTime + parkTimeout;
  repeat
    fRenderPending := true;
    RenderFrame;
    event := mpv_wait_event(fHandle, 0.002);
    case event^.event_id of
      MPV_EVENT_END_FILE:
        ended := true;
      MPV_EVENT_COMMAND_REPLY:
        if event^.reply_userdata = requestPark then
        begin
          Inc(replies);
          refused := refused or (event^.error < 0);
        end;
    end;
  until (ended and (replies = parkCommands)) or fFailed or (MonotonicTime >= deadline);
  if not ended or (replies <> parkCommands) or refused or fFailed then
    Exit;
  mpv_render_context_set_update_callback(fContext, nil, nil);
  repeat
    event := mpv_wait_event(fHandle, 0);
  until event^.event_id = MPV_EVENT_NONE;
  parkedHandle := fHandle;
  parkedContext := fContext;
  parkedTarget := fTarget;
  fHandle := nil;
  fContext := nil;
  fTarget := nil;
  fFrameTex := nil;
  fLibraryLoaded := false;
  Result := true;
end;

{ Asks for the codec name; SelectHardwareDecoder runs when the reply arrives.
  A synchronous read here would wait for mpv's core, which after the first
  frame of a new player can be waiting up to 200 ms for this thread to
  render. }
procedure TVideo_MPV.RequestHardwareDecoding;
var
  code: cint;
begin
  if fDecoderSwitchSent or (Ini.VideoHardwareDecoding = 'no') then
    Exit;
  fDecoderSwitchSent := true;
  code := mpv_get_property_async(fHandle, requestCodec, 'video-codec', MPV_FORMAT_STRING);
  if code < 0 then
  begin
    fDecoderProbed := true;
    Log.LogWarn('Cannot read the video codec: ' + MpvError(code), 'TVideo_MPV');
  end;
end;

{$IF Defined(LINUX) and Defined(CPUAARCH64)}
function UsePi5HEVCDecoder(const Codec: string): boolean;
const
  ModelPrefix = 'Raspberry Pi 5 Model B';
var
  ModelFile: TFileStream;
  Model: array[1..Length(ModelPrefix)] of AnsiChar;
begin
  Result := false;
  // Older libmpv versions append the codec description to the short name.
  if (Codec <> 'hevc') and (Pos('hevc (', Codec) <> 1) then
    Exit;
  try
    ModelFile := TFileStream.Create('/proc/device-tree/model', fmOpenRead or fmShareDenyNone);
    try
      Result := (ModelFile.Read(Model, SizeOf(Model)) = SizeOf(Model)) and
        CompareMem(@Model[1], PAnsiChar(ModelPrefix), SizeOf(Model));
    finally
      ModelFile.Free;
    end;
  except
    on E: EStreamError do
      Result := false;
  end;
end;
{$ENDIF}

procedure TVideo_MPV.SelectHardwareDecoder;
var
  wanted: AnsiString;
  value: PAnsiChar;
  index: integer;
  code: cint;
begin
  index := rememberedDecoders.IndexOfName(fCodec);
  if index >= 0 then
  begin
    wanted := AnsiString(rememberedDecoders.ValueFromIndex[index]);
    fDecoderProbed := true;
    Log.LogInfo('Using remembered decoder ' + wanted + ' for ' + fCodec, 'TVideo_MPV');
    if wanted = 'no' then
      Exit;
  end
  else
  begin
    wanted := AnsiString(Ini.VideoHardwareDecoding);
    {$IF Defined(LINUX) and Defined(CPUAARCH64)}
    // Direct DRM frames cannot be rendered on the Pi 5 stack we tested.
    // libmpv falls back to software if DRM copy-back cannot start.
    if (wanted = 'auto') and UsePi5HEVCDecoder(fCodec) then
      wanted := 'drm-copy';
    {$ENDIF}
    Log.LogInfo('Probing hardware decoding for ' + fCodec, 'TVideo_MPV');
  end;
  value := PAnsiChar(wanted);
  code := mpv_set_property_async(fHandle, requestHwdec, 'hwdec', MPV_FORMAT_STRING, @value);
  if code < 0 then
  begin
    fDecoderProbed := true;
    Log.LogWarn('Cannot request hardware decoding: ' + MpvError(code), 'TVideo_MPV');
  end;
end;

{ The decoder switch ends with a refresh seek; its PLAYBACK_RESTART means the
  new decoder produced a frame. Observed hwdec-current may still be queued
  behind that event, so PumpEvents asks for the final value and passes the
  reply here. }
procedure TVideo_MPV.RememberDecoder(Decoder: string);
begin
  if Decoder = '' then
    Decoder := 'no';
  if Decoder <> fHardwareDecoder then
  begin
    fHardwareDecoder := Decoder;
    fLoggedDecoder := false;
  end;
  if fCodec <> '' then
    rememberedDecoders.Values[fCodec] := Decoder;
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
    propertyEndReached:
      if value^.format = MPV_FORMAT_FLAG then
        fEndReached := pcint(value^.data)^ <> 0;
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
  reply: Pmpv_event_property;
  text: string;
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
      MPV_EVENT_PROPERTY_CHANGE:
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
        if fDecoderSwitchReplied and not fDecoderProbed then
        begin
          fDecoderProbed := true;
          if mpv_get_property_async(fHandle, requestDecoder, 'hwdec-current', MPV_FORMAT_STRING) < 0 then
            RememberDecoder('');
        end;
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
      MPV_EVENT_GET_PROPERTY_REPLY:
        if (event^.reply_userdata = requestCodec) or (event^.reply_userdata = requestDecoder) then
        begin
          reply := event^.data;
          text := '';
          if (event^.error >= 0) and (reply <> nil) and (reply^.format = MPV_FORMAT_STRING) and
             (reply^.data <> nil) and (mpv.PPAnsiChar(reply^.data)^ <> nil) then
            text := string(mpv.PPAnsiChar(reply^.data)^);
          if event^.reply_userdata = requestCodec then
          begin
            fCodec := text;
            SelectHardwareDecoder;
          end
          else
            RememberDecoder(text);
        end
        else if event^.error >= 0 then
          ReadProperty(event);
      MPV_EVENT_SET_PROPERTY_REPLY:
      begin
        if event^.reply_userdata = requestHwdec then
        begin
          { Software decoding continues when the request is refused. }
          if event^.error < 0 then
          begin
            fDecoderProbed := true;
            Log.LogWarn('Hardware decoding refused: ' + MpvError(event^.error), 'TVideo_MPV');
          end
          else
            fDecoderSwitchReplied := true;
        end
        else if event^.error < 0 then
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
    fSync.Reset;
    fSeekStarted := MonotonicTime;
    fSeekWanted := false;
    { The previous frame stays on screen until the seek result is rendered. }
    fEndReached := false;
  end;
end;

function TVideo_MPV.Open(const FileName: IPath; const Media: TBytes = nil): boolean;
var
  deadline: double;
  filenameUTF8: AnsiString;
begin
  Close;
  ResetPresentation;
  Result := false;
  { No in-memory input: TVideoPlayback_MPV.Open hands a snapshot to the fallback. }
  if Media <> nil then
    Exit;
  if not AdoptParkedPlayer() then
  begin
    fLibraryLoaded := LoadMpv();
    if not fLibraryLoaded then
      Exit;
  end;

  try
    if (fHandle = nil) and (not CreatePlayer() or not CreateContext()) then
      Exit;
    filenameUTF8 := FileName.GetAbsolutePath().ToUTF8();
    if not Command(requestLoad, ['loadfile', filenameUTF8, 'replace']) then
      Exit;

    deadline := MonotonicTime + openTimeout;
    repeat
      PumpEvents;
      if fFileLoaded and fPlaybackStarted and not fInitialRead then
        ReadInitialProperties;
      RenderFrame;
      if fFailed then
        Exit;
      if fFileLoaded and fPlaybackStarted and fFrameTexValid then
      begin
        fOpened := true;
        Log.LogInfo('Using libmpv video (' + IntToStr(fVideoWidth) + 'x' +
          IntToStr(fVideoHeight) + ') for ' + FileName.ToUTF8(), 'TVideo_MPV');
        RequestHardwareDecoding;
        Exit(true);
      end;
      { keep-open holds a cleanly ended file instead of sending END_FILE.
        Without a frame by then, none will arrive before the timeout. }
      if fFileLoaded and fPlaybackStarted and fEndReached then
      begin
        Fail('libmpv reached the end without a video frame');
        Exit;
      end;
      SDL_Delay(1);
    until MonotonicTime >= deadline;
    Fail(Format('Timed out opening video with libmpv (loaded %s, started %s, %dx%d)',
      [BoolToStr(fFileLoaded, true), BoolToStr(fPlaybackStarted, true), fVideoWidth, fVideoHeight]));
  finally
    if not fOpened then
      Close;
  end;
end;

procedure TVideo_MPV.Close;
begin
  ParkPlayer;
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
  fEndReached := false;
  fHardwareDecoder := '';
  fLoggedDecoder := false;
  fCodec := '';
  fDecoderSwitchSent := false;
  fDecoderSwitchReplied := false;
  fDecoderProbed := false;
  fInitialRead := false;
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
  if fPaused or fStopped then
    fSync.Resume
  else
    fSync.Reset;
  fPaused := false;
  fStopped := false;
end;

procedure TVideo_MPV.Pause;
begin
  fPaused := not fPaused;
  if fPaused then
  begin
    fDesiredPause := true;
    fDesiredSpeed := 1;
    ApplyControl;
  end
  else
    fSync.Resume;
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

function TVideo_MPV.Finished: boolean;
begin
  { keep-open holds the last frame at the end; a looping file never ends.
    After a failure in mid-stream GetFrame stops updating, so the caller must
    be able to drop the stale image. The FFmpeg backend also reports a decode
    failure as finished. }
  Result := fOpened and (fFailed or (fEndReached and not fLoop));
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
      fLoop, fPaused or fStopped, fEndReached);
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
  if fFrameTexValid then
    inherited Draw;
end;

initialization
  rememberedDecoders := TStringList.Create;
  MediaManager.Insert(0, TVideoPlayback_MPV.Create);

finalization
  rememberedDecoders.Free;

end.
