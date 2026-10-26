{ Renderer and video integration checks. run-video-smoke.py supplies the
  application's unit list so this tests the real backends without the UI.
  Distributed under the GNU General Public License, version 2 or later. }

type
  // Disable one renderer capability to exercise the real backend fallback path.
  TRendererTestAccess = class(TRenderer_OpenGLBase);

var
  Context: TSDL_GLContext;
  A, B: TRenderTarget;
  Profile, Major, Minor: integer;
  Pixel: array[0..3] of byte;
  ModeName: string;

procedure Require(Condition: boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

procedure CheckError(const Where: string);
var Code: cardinal;
begin
  Code := glGetError();
  Require(Code = GL_NO_ERROR, Where + ': GL error ' + IntToStr(Code));
end;

procedure CheckInt(Name: GLenum; Expected: integer; const What: string);
var Value: GLint;
begin
  glGetIntegerv(Name, @Value);
  Require(Value = Expected, What + ' got ' + IntToStr(Value) + ', expected ' + IntToStr(Expected));
end;

function FindVideoProvider(const Name: string): IVideoPlayback;
var I: integer; Candidate: IVideoPlayback;
begin
  Result:=nil;
  for I:=0 to MediaManager.Count-1 do
    if Supports(MediaManager[I],IVideoPlayback,Candidate) and (Candidate.GetName=Name) then
      Exit(Candidate);
end;

procedure TestVideoSelection;
var
  SavedProviders: array of IInterface;
  FFmpegProvider, MpvProvider: IVideoPlayback;
  I: integer;
begin
  ConsoleWriteLn('Testing configured video provider selection');
  FFmpegProvider:=FindVideoProvider('FFmpeg_Video');
  MpvProvider:=FindVideoProvider('MPV_Video');
  Require(FFmpegProvider<>nil,'missing FFmpeg provider');
  SetLength(SavedProviders,MediaManager.Count);
  for I:=0 to MediaManager.Count-1 do
    SavedProviders[I]:=MediaManager[I];
  try
    // Exercise the application's selector without initializing visualizers.
    MediaManager.Clear;
    if MpvProvider<>nil then MediaManager.Add(MpvProvider);
    MediaManager.Add(FFmpegProvider);
    Ini.VideoBackend:='ffmpeg';
    InitializeVideo;
    Require(VideoPlayback=FFmpegProvider,'FFmpeg preference was ignored');
    {$IFDEF UseMpvVideo}
    Require(MpvProvider<>nil,'missing MPV provider');
    Require(FindVideoProvider('MPV_Video')=MpvProvider,
      'disabled MPV provider was treated as an initialization failure');
    Ini.VideoBackend:='mpv';
    InitializeVideo;
    Require(VideoPlayback=MpvProvider,'MPV preference was ignored');
    // A previously initialized optional provider must still respect opt-out.
    Ini.VideoBackend:='ffmpeg';
    InitializeVideo;
    Require(VideoPlayback=FFmpegProvider,'initialized MPV overrode FFmpeg preference');
    {$ENDIF}
  finally
    if MpvProvider<>nil then MpvProvider.Finalize;
    MediaManager.Clear;
    for I:=0 to High(SavedProviders) do
      MediaManager.Add(SavedProviders[I]);
    Ini.VideoBackend:='mpv';
  end;
  ConsoleWriteLn('PASS configured video provider selection');
end;

procedure RenderVideo(const Video: IVideo; Time: double);
begin
  Video.GetFrame(Time);
  Renderer.SetClearColor(0.5,0.5,0.5,1);
  Renderer.ClearFrameBuffer(CLEAR_COLOR);
  Video.Draw;
  CheckError('video render');
end;

procedure PumpVideo(const Video: IVideo; StartTime: double; Milliseconds: cardinal; Advance: boolean);
var Started, NowTick: cardinal; Time: double;
begin
  Started:=SDL_GetTicks;
  repeat
    NowTick:=SDL_GetTicks;
    Time:=StartTime;
    if Advance then Time:=Time+(NowTick-Started)/1000;
    RenderVideo(Video,Time);
    SDL_PumpEvents;
    SDL_Delay(10);
  until NowTick-Started>=Milliseconds;
end;

procedure CheckVideoColors(Phase: integer; const Where: string);
const
  Colors: array[0..3,0..2] of byte=((255,0,0),(0,255,0),(0,0,255),(255,255,0));
var X,Y,C,Q: integer; Actual: array[0..3] of byte;
begin
  for Y:=0 to 1 do
    for X:=0 to 1 do
    begin
      glReadPixels(16+32*X,24-16*Y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,@Actual[0]);
      Q:=(Y*2+X+Phase) mod 4;
      for C:=0 to 2 do
        Require(Abs(integer(Actual[C])-Colors[Q,C])<55,
          Where+' quadrant '+IntToStr(Y*2+X)+' RGB '+IntToStr(Actual[0])+','+IntToStr(Actual[1])+','+IntToStr(Actual[2]));
    end;
end;

procedure TestVideo(const ProviderName: string);
var Provider: IVideoPlayback; Video: IVideo;
begin
  Provider:=FindVideoProvider(ProviderName);
  Require(Provider<>nil,'missing '+ProviderName);
  Require(Provider.Init,'cannot initialize '+ProviderName);
  Video:=Provider.Open(Path(ParamStr(2)));
  Require(Video<>nil,'cannot open video '+ProviderName);
  ConsoleWriteLn('Testing ' + ProviderName);
  PumpVideo(Video,0,250,false);
  CheckVideoColors(0,ProviderName+' initial orientation');
  Video.Play;
  PumpVideo(Video,0,1400,true);
  CheckVideoColors(1,ProviderName+' advancing clock');
  Video.Pause;
  PumpVideo(Video,1.4,300,false);
  CheckVideoColors(1,ProviderName+' pause');
  if ProviderName='FFmpeg_Video' then Video.Pause;
  Video.SetPosition(2.2);
  PumpVideo(Video,2.2,500,false);
  CheckVideoColors(2,ProviderName+' seek');
  Video.Play;
  Video.SetLoop(true);
  Video.SetPosition(3.2);
  PumpVideo(Video,3.2,250,false);
  CheckVideoColors(3,ProviderName+' seek before loop');
  PumpVideo(Video,3.2,1300,true);
  CheckVideoColors(0,ProviderName+' loop boundary');
  Video.SetLoop(false);
  Video.SetPosition(3.2);
  PumpVideo(Video,3.2,250,false);
  PumpVideo(Video,3.2,2800,true);
  CheckVideoColors(3,ProviderName+' end of video');
  Video.Stop;
  Video:=nil;
  CheckError('video destruction '+ProviderName);
  Provider.Finalize;
  ConsoleWriteLn('PASS ' + ProviderName + ': orientation, advance, pause, seek, loop, EOF, destruction');
end;

{$IFDEF UseMpvVideo}
procedure TestVideoStartup;
var Provider: IVideoPlayback; Video: IVideo; I: integer; Saved: string; Wait: cardinal;
begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  Require(Provider.Init,'cannot initialize MPV provider for startup test');
  Saved:=Ini.VideoHardwareDecoding;
  if Saved='no' then Ini.VideoHardwareDecoding:='auto';
  try
    for I:=1 to 5 do
    begin
      Video:=Provider.Open(Path(ParamStr(2)));
      Require(Video<>nil,'cannot reopen MPV video');
      ConsoleWriteLn('Testing MPV_Video startup ' + IntToStr(I));
      // The first and last open wait for the decoder switch after frame 0; the
      // others close while the reused player is still switching.
      if (I=1) or (I=5) then Wait:=3000 else Wait:=100;
      PumpVideo(Video,0,Wait,false);
      CheckVideoColors(0,'MPV startup '+IntToStr(I));
      Video:=nil;
    end;
  finally
    Ini.VideoHardwareDecoding:=Saved;
  end;
  Provider.Finalize;
  CheckError('repeated startup/destruction');
  ConsoleWriteLn('PASS MPV startup: five paused initial frames, player reuse and decoder memory');
end;

procedure TestVideoFallback;
var Provider: IVideoPlayback; Video: IVideo; SupportsTargets: boolean;
begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  Require(Provider.Init,'cannot initialize MPV provider for fallback test');
  ConsoleWriteLn('Testing expected errors for missing/corrupt files');
  Video:=Provider.Open(Path(ParamStr(2)+'.missing'));
  Require(Video=nil,'missing file returned a video');
  Video:=Provider.Open(Path(ParamStr(2)+'.corrupt'));
  Require(Video=nil,'corrupt file returned a video');
  ConsoleWriteLn('Testing expected libmpv initialization failure and FFmpeg fallback');
  SupportsTargets:=TRendererTestAccess(Renderer).SupportsFBO;
  TRendererTestAccess(Renderer).SupportsFBO:=false;
  try
    Video:=Provider.Open(Path(ParamStr(2)));
  finally
    TRendererTestAccess(Renderer).SupportsFBO:=SupportsTargets;
  end;
  Require(Video<>nil,'fallback did not open valid video');
  PumpVideo(Video,0,100,false);
  CheckVideoColors(0,'FFmpeg fallback');
  Video:=nil;
  Provider.Finalize;
  CheckError('fallback video destruction');
  ConsoleWriteLn('PASS fallback: missing/corrupt files rejected, FFmpeg opens after libmpv failure');
end;
{$ENDIF}

procedure Run;
var I: integer; Saved: array[0..3] of GLint;
begin
  SetDefaultNumericLocale;
  Log.SetLogLevel(LOG_LEVEL_INFO);
  Ini := TIni.Create;
  Ini.VideoBackend:='mpv';
  Ini.VideoHardwareDecoding:=ParamStr(3);
  if Ini.VideoHardwareDecoding='' then Ini.VideoHardwareDecoding:='no';
  SDL_SetHint(SDL_HINT_WINDOWS_DISABLE_THREAD_NAMING, '1');
  if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_TIMER) <> 0 then
    raise Exception.Create('SDL initialization failed: ' + string(SDL_GetError()));
  ModeName := ParamStr(1);
  if ModeName = 'gles2' then begin Major:=2; Minor:=0; Profile:=SDL_GL_CONTEXT_PROFILE_ES; end
  else if ModeName = 'gles3' then begin Major:=3; Minor:=0; Profile:=SDL_GL_CONTEXT_PROFILE_ES; end
  else if ModeName = 'gl2' then begin Major:=2; Minor:=1; Profile:=SDL_GL_CONTEXT_PROFILE_COMPATIBILITY; end
  else begin Major:=3; Minor:=3; Profile:=SDL_GL_CONTEXT_PROFILE_CORE; end;
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, Major);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, Minor);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, Profile);
  Screen := SDL_CreateWindow('USDX offscreen smoke', 0, 0, 64, 32, SDL_WINDOW_OPENGL or SDL_WINDOW_HIDDEN);
  if Screen = nil then raise Exception.Create('SDL window failed: ' + string(SDL_GetError()));
  Context := SDL_GL_CreateContext(Screen);
  if Context = nil then raise Exception.Create('SDL GL context failed: ' + string(SDL_GetError()));
  RenderW:=64; RenderH:=32; ScreenW:=64; ScreenH:=32; ScreenWPerScreen:=64;
  VertexW:=1; VertexH:=1; Screens:=1; ScreenAct:=1;
  if Profile = SDL_GL_CONTEXT_PROFILE_ES then Renderer := TRenderer_OpenGLES.Create(Context, Major, Minor)
  else if Major >= 3 then Renderer := TRenderer_OpenGL3.Create(Context, Major, Minor)
  else Renderer := TRenderer_OpenGL2.Create(Context, Major, Minor);
  Renderer.SetOrthographicProjection(0,64,32,0,-10,10);
  Renderer.SetViewPort(0,0,64,32);
  Renderer.DepthTest:=false;
  Renderer.Blend:=false;
  Renderer.ScissorTest:=false;
  CheckError('renderer initialized');
  Require(Renderer.CreateRenderTarget(0,32) = nil,'invalid target size accepted');
  Require(Renderer.CreateRenderTarget(Renderer.MaxTextureSize+1,32) = nil,'oversized target accepted');
  A := Renderer.CreateRenderTarget(64,32);
  Require(A <> nil,'render target unsupported');
  CheckError('target created');
  if ModeName <> 'gles2' then
  begin
    glBindFramebuffer(GL_READ_FRAMEBUFFER,A.NativeHandle);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER,0);
    B := Renderer.CreateRenderTarget(31,17);
    Require(B <> nil,'second target unsupported');
    CheckInt(GL_READ_FRAMEBUFFER_BINDING,A.NativeHandle,'read framebuffer after create');
    CheckInt(GL_DRAW_FRAMEBUFFER_BINDING,0,'draw framebuffer after create');
    B.BeginRender;
    glBindFramebuffer(GL_FRAMEBUFFER,0);
    B.EndRender;
    CheckInt(GL_READ_FRAMEBUFFER_BINDING,A.NativeHandle,'read framebuffer after external render');
    CheckInt(GL_DRAW_FRAMEBUFFER_BINDING,0,'draw framebuffer after external render');
    B.Free;
    glBindFramebuffer(GL_FRAMEBUFFER,0);
  end;
  Renderer.SetViewPort(2,3,40,20);
  glEnable(GL_BLEND); glEnable(GL_SCISSOR_TEST);
  glBlendFuncSeparate(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA,GL_ONE,GL_ZERO);
  glScissor(1,2,30,15);
  A.BeginRender;
  glViewport(0,0,64,32);
  glClearColor(1,0,0,1);
  glClear(GL_COLOR_BUFFER_BIT);
  glDisable(GL_BLEND); glDisable(GL_SCISSOR_TEST);
  glBlendFunc(GL_ONE,GL_ONE);
  A.EndRender;
  glGetIntegerv(GL_VIEWPORT,@Saved[0]);
  Require((Saved[0]=2) and (Saved[1]=3) and (Saved[2]=40) and (Saved[3]=20),'viewport not restored');
  Require(glIsEnabled(GL_BLEND),'blend not restored');
  Require(glIsEnabled(GL_SCISSOR_TEST),'scissor enable not restored');
  CheckInt(GL_BLEND_SRC_RGB,GL_SRC_ALPHA,'blend source');
  CheckInt(GL_BLEND_DST_RGB,GL_ONE_MINUS_SRC_ALPHA,'blend destination');
  CheckError('external state restored');
  Renderer.SetViewPort(0,0,64,32);
  Renderer.Blend:=false; Renderer.ScissorTest:=false;
  Renderer.SetClearColor(0,0,1,1); Renderer.ClearFrameBuffer(CLEAR_COLOR);
  A.Texture.X:=0; A.Texture.Y:=0; A.Texture.Z:=0; A.Texture.W:=64; A.Texture.H:=32;
  Renderer.DrawTexture(A.Texture);
  glReadPixels(32,16,1,1,GL_RGBA,GL_UNSIGNED_BYTE,@Pixel[0]);
  Require((Pixel[0]>240) and (Pixel[1]<10) and (Pixel[2]<10),'render target texture was not drawn red');
  CheckError('target drawn by USDX');
  A.Free; A:=nil;
  for I:=1 to 20 do
  begin
    A:=Renderer.CreateRenderTarget(31,17);
    Require(A<>nil,'repeat target allocation');
    A.Free; A:=nil;
  end;
  CheckError('target destruction');
  ConsoleWriteLn('PASS ' + ModeName + ': offscreen texture output, state restoration, framebuffer separation and repeated lifetime');
  if ParamStr(2)<>'' then
  begin
    TestVideoSelection;
    TestVideo('FFmpeg_Video');
    {$IFDEF UseMpvVideo}
    TestVideo('MPV_Video');
    TestVideoStartup;
    TestVideoFallback;
    {$ENDIF}
  end;
  Renderer.Free; Renderer:=nil;
  SDL_DestroyWindow(Screen); Screen:=nil; SDL_Quit;
  Ini.Free; Ini:=nil;
end;
begin
  try Run; except on E: Exception do begin ConsoleWriteLn(E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
