{ Renderer and video integration checks. run-video-smoke.py supplies the
  application's unit list so this tests the real backends without the UI.
  Arguments: <renderer> [<fixture> <hwdec> [missing-mpv]].
  Distributed under the GNU General Public License, version 2 or later. }

type
  // Disable one renderer capability to exercise the real backend fallback path.
  TRendererTestAccess = class(TRenderer_OpenGLBase);
  TScreenPixels = array[0..64*32*4-1] of byte;
  TProviderList = array of IInterface;

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

function VideoClass(const Video: IVideo): string;
begin
  Result:='nil';
  if Video<>nil then Result:=(Video as TObject).ClassName;
end;

// Leave only the video providers registered, in the application's order, so
// that InitializeVideo runs its real selection without starting visualizers.
procedure KeepVideoProvidersOnly(out Saved: TProviderList; out FFmpegProvider, MpvProvider: IVideoPlayback);
var I: integer;
begin
  FFmpegProvider:=FindVideoProvider('FFmpeg_Video');
  MpvProvider:=FindVideoProvider('MPV_Video');
  Require(FFmpegProvider<>nil,'missing FFmpeg provider');
  SetLength(Saved,MediaManager.Count);
  for I:=0 to MediaManager.Count-1 do Saved[I]:=MediaManager[I];
  MediaManager.Clear;
  if MpvProvider<>nil then MediaManager.Add(MpvProvider);
  MediaManager.Add(FFmpegProvider);
end;

procedure RestoreProviders(const Saved: TProviderList; const MpvProvider: IVideoPlayback);
var I: integer;
begin
  if MpvProvider<>nil then MpvProvider.Finalize;
  MediaManager.Clear;
  for I:=0 to High(Saved) do MediaManager.Add(Saved[I]);
end;

procedure RequireSamePixels(const Expected, Actual: TScreenPixels; const Where: string);
var I: integer;
begin
  for I:=0 to High(Expected) do
    Require(Expected[I]=Actual[I],Where+': pixel '+IntToStr(I div 4 mod 64)+','+IntToStr(I div 256)+
      ' channel '+IntToStr(I mod 4)+' is '+IntToStr(Actual[I])+', expected '+IntToStr(Expected[I]));
end;

procedure TestVideoSelection;
var
  Saved: TProviderList;
  FFmpegProvider, MpvProvider: IVideoPlayback;

  procedure ExpectBackend(const Backend, VideoType: string);
  var Video: IVideo;
  begin
    {$IFDEF UseMpvVideo}
    Ini.VideoBackend:=Backend;
    {$ENDIF}
    Video:=VideoPlayback.Open(Path(ParamStr(2)));
    Require(VideoClass(Video)=VideoType,'backend '+Backend+' opened '+VideoClass(Video)+', expected '+VideoType);
  end;

begin
  ConsoleWriteLn('Testing configured video provider selection');
  KeepVideoProvidersOnly(Saved,FFmpegProvider,MpvProvider);
  try
    {$IFDEF UseMpvVideo}
    Ini.VideoBackend:='ffmpeg';
    {$ENDIF}
    InitializeVideo;
    {$IFDEF UseMpvVideo}
    // The optional provider is selected whatever the setting and reads the
    // setting at every open, so a change needs no new initialization.
    Require(MpvProvider<>nil,'missing MPV provider');
    Require(VideoPlayback=MpvProvider,'the MPV provider was not selected');
    ExpectBackend('ffmpeg','TVideo_FFmpeg');
    ExpectBackend('mpv','TVideo_MPV');
    ExpectBackend('ffmpeg','TVideo_FFmpeg');
    {$ELSE}
    Require(VideoPlayback=FFmpegProvider,'FFmpeg was not selected');
    ExpectBackend('ffmpeg','TVideo_FFmpeg');
    {$ENDIF}
  finally
    RestoreProviders(Saved,MpvProvider);
    {$IFDEF UseMpvVideo}
    Ini.VideoBackend:='mpv';
    {$ENDIF}
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

function VideoColorsMatch(Phase: integer; out Detail: string): boolean;
const
  Colors: array[0..3,0..2] of byte=((255,0,0),(0,255,0),(0,0,255),(255,255,0));
var X,Y,C,Q: integer; Actual: array[0..3] of byte;
begin
  Result:=false;
  for Y:=0 to 1 do
    for X:=0 to 1 do
    begin
      glReadPixels(16+32*X,24-16*Y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,@Actual[0]);
      Q:=(Y*2+X+Phase) mod 4;
      for C:=0 to 2 do
        if Abs(integer(Actual[C])-Colors[Q,C])>=55 then
        begin
          Detail:=' quadrant '+IntToStr(Y*2+X)+' RGB '+IntToStr(Actual[0])+','+
            IntToStr(Actual[1])+','+IntToStr(Actual[2]);
          Exit;
        end;
    end;
  Detail:='';
  Result:=true;
end;

procedure CheckVideoColors(Phase: integer; const Where: string);
var Detail: string; Matches: boolean;
begin
  Matches:=VideoColorsMatch(Phase,Detail);
  Require(Matches,Where+Detail);
end;

// FFmpeg decodes asynchronously. Wait for the paused first frame rather than
// assuming the decode thread was scheduled within a fixed 100 or 250 ms.
procedure WaitFirstVideoFrame(const Video: IVideo; const Where: string);
var Started: cardinal; Detail: string;
begin
  Started:=SDL_GetTicks;
  repeat
    RenderVideo(Video,0);
    if VideoColorsMatch(0,Detail) then Exit;
    SDL_PumpEvents;
    SDL_Delay(10);
  until SDL_GetTicks-Started>=3000;
  CheckVideoColors(0,Where+' after waiting for the first frame');
end;

procedure TestVideo(const ProviderName: string);
var Provider: IVideoPlayback; Video: IVideo;
begin
  Provider:=FindVideoProvider(ProviderName);
  Require(Provider<>nil,'missing '+ProviderName);
  Require(Provider.Init,'cannot initialize '+ProviderName);
  ConsoleWriteLn('Testing ' + ProviderName);
  Video:=Provider.Open(Path(ParamStr(2)));
  Require(Video<>nil,'cannot open video '+ProviderName);
  WaitFirstVideoFrame(Video,ProviderName+' initial orientation');
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

{ The shared menu background: real menu objects, their cache and both backends. }
{$IFDEF UseMpvVideo}
type
  TMenuMpvSetProperty = function(Handle: Pmpv_handle; ReplyUserdata: UInt64;
    Name: PAnsiChar; Format: longint; Data: Pointer): longint; cdecl;
var
  MenuOriginalSetProperty: TMenuMpvSetProperty;
  MenuUnpauseSubmitted: boolean;

function ObserveMenuSetProperty(Handle: Pmpv_handle; ReplyUserdata: UInt64;
  Name: PAnsiChar; Format: longint; Data: Pointer): longint; cdecl;
begin
  // Observe the real request without changing, dropping or delaying it.
  Result:=MenuOriginalSetProperty(Handle,ReplyUserdata,Name,Format,Data);
  if (Result>=0) and (Name<>nil) and (Data<>nil) and
     (string(Name)='pause') and (Format=MPV_FORMAT_FLAG) and
     (PLongint(Data)^=0) then MenuUnpauseSubmitted:=true;
end;
{$ENDIF}

procedure TestRetainedMenuVideo(const ProviderName: string);
var
  Provider: IVideoPlayback;
  {$IFDEF UseMpvVideo}
  SavedBackend: string;
  {$ENDIF}
  SavedSkin, TestSkin: TSkin;
  SavedThemePaths: IInterfaceList;
  Settings: TThemeBackground;
  FileName: IPath;
  First, Second: TMenuBackgroundVideo;

  procedure DrawMenuVideo(Menu: TMenuBackgroundVideo);
  begin
    Renderer.SetClearColor(0.5,0.5,0.5,1);
    Renderer.ClearFrameBuffer(CLEAR_COLOR);
    Menu.Draw;
    CheckError('retained menu video '+ProviderName);
  end;

  procedure PumpMenu(Menu: TMenuBackgroundVideo; Milliseconds: cardinal);
  var Started: cardinal;
  begin
    Started:=SDL_GetTicks;
    repeat
      DrawMenuVideo(Menu);
      SDL_PumpEvents;
      SDL_Delay(10);
    until SDL_GetTicks-Started>=Milliseconds;
  end;

  procedure HideAfterUnpause;
  {$IFDEF UseMpvVideo}
  var Started: cardinal;
  {$ENDIF}
  begin
    {$IFDEF UseMpvVideo}
    if ProviderName='MPV_Video' then
    begin
      Require(Assigned(mpv_set_property_async),'missing MPV property binding');
      MenuOriginalSetProperty:=mpv_set_property_async;
      MenuUnpauseSubmitted:=false;
      mpv_set_property_async:=@ObserveMenuSetProperty;
      try
        First.OnShow;
        Started:=SDL_GetTicks;
        repeat
          DrawMenuVideo(First);
          if MenuUnpauseSubmitted then Break;
          SDL_Delay(10);
        until SDL_GetTicks-Started>=250;
        Require(MenuUnpauseSubmitted,'menu did not submit an MPV unpause');
        // No intervening GetFrame can consume this request's acknowledgment:
        // the backend still has an unpause pending when the last user hides.
        First.OnFinish;
      finally
        mpv_set_property_async:=MenuOriginalSetProperty;
        MenuOriginalSetProperty:=nil;
      end;
      Exit;
    end;
    {$ENDIF}
    First.OnShow;
    PumpMenu(First,20);
    First.OnFinish;
  end;

begin
  ConsoleWriteLn('Testing retained menu video '+ProviderName);
  // TestVideoSelection has initialized the application's selector. A backend
  // setting change applies to its next Open, including menu constructors.
  Provider:=VideoPlayback;
  Require(Provider<>nil,'missing menu video provider');
  {$IFDEF UseMpvVideo}
  SavedBackend:=Ini.VideoBackend;
  if ProviderName='FFmpeg_Video' then Ini.VideoBackend:='ffmpeg'
  else Ini.VideoBackend:='mpv';
  {$ENDIF}
  Require(Provider.Init,'cannot initialize '+ProviderName+' for menu cache');
  SavedSkin:=Skin;
  SavedThemePaths:=ThemePaths;
  TestSkin:=nil; First:=nil; Second:=nil;
  ClearMenuVideoCache;
  try
    // TSkin.Create scans ThemePaths, which this program never fills: give it
    // an empty list. The skin then only binds one texture name to the fixture.
    ThemePaths:=TInterfaceList.Create;
    TestSkin:=TSkin.Create;
    ThemePaths:=SavedThemePaths;
    Skin:=TestSkin;
    FileName:=Path(ParamStr(2));
    Skin.SetTextureEntry('VideoSmoke',FileName.GetName,FileName.GetPath);
    Settings:=DEFAULT_BACKGROUND;
    Settings.BGType:=bgtVideo;
    Settings.Tex:='VideoSmoke';
    First:=TMenuBackgroundVideo.Create(Settings);
    Second:=TMenuBackgroundVideo.Create(Settings);
    First.OnShow;
    PumpMenu(First,350);
    CheckVideoColors(0,ProviderName+' menu initial frame');
    Second.OnShow;
    PumpMenu(Second,900);
    CheckVideoColors(1,ProviderName+' acquiring another menu must not pause');
    First.OnFinish;
    PumpMenu(Second,900);
    CheckVideoColors(2,ProviderName+' releasing one menu must not pause another');

    // Retain the same cached video while every user is hidden. In particular,
    // do not call Draw/GetFrame, close the video or finalize its provider.
    Second.OnFinish;
    SDL_Delay(1100);
    First.OnShow;
    PumpMenu(First,200);
    CheckVideoColors(2,ProviderName+' hidden cached menu advanced or reopened');
    First.OnFinish;
    SDL_Delay(50);
    HideAfterUnpause;
    SDL_Delay(1100);
    First.OnShow;
    PumpMenu(First,200);
    CheckVideoColors(2,ProviderName+' immediately hidden menu advanced');
    PumpMenu(First,850);
    CheckVideoColors(3,ProviderName+' cached menu did not resume');
  finally
    First.Free;
    Second.Free;
    ClearMenuVideoCache;
    Skin:=SavedSkin;
    TestSkin.Free;
    ThemePaths:=SavedThemePaths;
    Provider.Finalize;
    {$IFDEF UseMpvVideo}
    Ini.VideoBackend:=SavedBackend;
    {$ENDIF}
  end;
  CheckError('menu cache destruction '+ProviderName);
  ConsoleWriteLn('PASS retained menu video '+ProviderName+
    ': shared users, hidden cache, immediate hide and resumed playback');
end;

{$IFDEF UseMpvVideo}
procedure TestVideoStartup;
var Provider: IVideoPlayback; Video: IVideo; I: integer; Wait: cardinal;
begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  Require(Provider.Init,'cannot initialize MPV provider for startup test');
  for I:=1 to 5 do
  begin
    Video:=Provider.Open(Path(ParamStr(2)));
    Require(Video<>nil,'cannot reopen MPV video');
    ConsoleWriteLn('Testing MPV_Video startup ' + IntToStr(I));
    // The first and last open wait for a decoder switch after frame 0; the
    // others close while the reused player may still be switching.
    if (I=1) or (I=5) then Wait:=3000 else Wait:=100;
    PumpVideo(Video,0,Wait,false);
    CheckVideoColors(0,'MPV startup '+IntToStr(I));
    Video:=nil;
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
  SupportsTargets:=TRendererTestAccess(Renderer).SupportsRenderTargets;
  TRendererTestAccess(Renderer).SupportsRenderTargets:=false;
  try
    Video:=Provider.Open(Path(ParamStr(2)));
  finally
    TRendererTestAccess(Renderer).SupportsRenderTargets:=SupportsTargets;
  end;
  Require(Video<>nil,'fallback did not open valid video');
  WaitFirstVideoFrame(Video,'FFmpeg fallback');
  Video:=nil;
  Provider.Finalize;
  CheckError('fallback video destruction');
  ConsoleWriteLn('PASS fallback: missing/corrupt files rejected, FFmpeg opens after libmpv failure');
end;

procedure TestVideoWithoutFrame;
var Provider: IVideoPlayback; Video: IVideo; Started, Elapsed: cardinal;
begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  Require(Provider.Init,'cannot initialize MPV provider for end-of-file test');
  ConsoleWriteLn('Testing libmpv end without a video frame');
  Started:=SDL_GetTicks;
  Video:=Provider.Open(Path(ParamStr(2)+'.noframe'));
  Elapsed:=SDL_GetTicks-Started;
  // The FFmpeg fallback may accept the file; only libmpv's wait is checked.
  Video:=nil;
  Provider.Finalize;
  CheckError('end-of-file video destruction');
  // libmpv's open timeout is 5 s; failing over must not wait for it.
  Require(Elapsed<3000,'libmpv took '+IntToStr(Elapsed)+' ms to give up on a stream without frames');
  ConsoleWriteLn('PASS libmpv end without a frame: gave up after '+IntToStr(Elapsed)+' ms');
end;

function ReadBytes(const FileName: string): TBytes;
var F: file;
begin
  AssignFile(F,FileName);
  Reset(F,1);
  try
    Result:=nil;
    SetLength(Result,FileSize(F));
    if Length(Result)>0 then BlockRead(F,Result[0],Length(Result));
  finally
    CloseFile(F);
  end;
end;

procedure WriteBytes(const FileName: string; const Data: TBytes);
var F: file;
begin
  AssignFile(F,FileName);
  Rewrite(F,1);
  try
    if Length(Data)>0 then BlockWrite(F,Data[0],Length(Data));
  finally
    CloseFile(F);
  end;
end;

{$IFDEF Linux}
function readlink(Name, Buffer: PAnsiChar; Size: SizeUInt): SizeInt; cdecl; external 'c';

// Counts this process's file descriptors that refer to FileName.
function OpenHandles(const FileName: string): integer;
var Entry: TSearchRec; Link: array[0..4095] of AnsiChar; Count: SizeInt; Target: string;
begin
  Result:=0;
  if FindFirst('/proc/self/fd/*',faAnyFile,Entry)<>0 then
    raise Exception.Create('cannot list /proc/self/fd');
  try
    repeat
      Count:=readlink(PAnsiChar(AnsiString('/proc/self/fd/'+Entry.Name)),@Link[0],SizeOf(Link));
      if Count<=0 then Continue;
      SetString(Target,PAnsiChar(@Link[0]),Count);
      // A replaced file that is still open reads "<name> (deleted)".
      if (Target=FileName) or (Target=FileName+' (deleted)') then Inc(Result);
    until FindNext(Entry)<>0;
  finally
    FindClose(Entry);
  end;
end;
{$ENDIF}

procedure TestVideoPreview;
var Provider: IVideoPlayback; Video: IVideo; Media: TBytes; Source: string;
begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  Require(Provider.Init,'cannot initialize MPV provider for the preview test');
  Ini.VideoBackend:='mpv';
  ConsoleWriteLn('Testing in-memory preview with MPV selected');
  // Song selection reads the preview into memory, as TPreviewMediaLoad does.
  Media:=ReadBytes(ParamStr(2));
  Source:=ExpandFileName('preview.mp4');
  WriteBytes(Source,Media);
  Video:=Provider.Open(Path(Source),Media);
  Require(VideoClass(Video)='TVideo_FFmpeg','the snapshot opened as '+VideoClass(Video));
  WaitFirstVideoFrame(Video,'preview initial orientation');
  Video.Play;
  PumpVideo(Video,0,1400,true);
  CheckVideoColors(1,'preview advancing clock');
  {$IFDEF Linux}
  Require(OpenHandles(Source)=0,'the preview holds its file open');
  {$ENDIF}
  // Replace the file the way a song editor or download does: write a new
  // file and rename it over the old one. Windows cannot rename over a file.
  WriteBytes(Source+'.new',BytesOf('replaced'));
  {$IFDEF MSWINDOWS}
  Require(DeleteFile(Source),'cannot delete the preview file while it plays');
  {$ENDIF}
  Require(RenameFile(Source+'.new',Source),'cannot replace the preview file');
  PumpVideo(Video,1.4,1900,true);
  CheckVideoColors(3,'preview after its file was replaced');
  PumpVideo(Video,3.3,1200,true);
  Require(Video.Finished,'the preview did not finish at the end of its snapshot');
  CheckVideoColors(3,'preview end of snapshot');
  {$IFDEF Linux}
  Require(OpenHandles(Source)=0,'the preview holds its file open');
  {$ENDIF}
  Video:=nil;
  CheckError('preview destruction');
  Provider.Finalize;
  ConsoleWriteLn('PASS in-memory preview: FFmpeg plays the snapshot to its end, the file stays replaceable');
end;

// Menu content drawn with the renderer calls menus use, read back from the window.
procedure DrawMenu(Texture: TTexture; out Pixels: TScreenPixels);
begin
  Renderer.SetClearColor(0.2,0.3,0.4,1);
  Renderer.ClearFrameBuffer(CLEAR_COLOR);
  Renderer.Blend:=true;
  Texture.X:=4; Texture.Y:=4; Texture.Z:=0; Texture.W:=24; Texture.H:=24;
  Renderer.DrawTexture(Texture);
  Renderer.DrawQuad(20,8,0,40,16,1,0.5,0,0.6);
  glReadPixels(0,0,64,32,GL_RGBA,GL_UNSIGNED_BYTE,@Pixels[0]);
  CheckError('menu drawing');
end;

procedure TestMenuAfterVideo;
var
  Provider: IVideoPlayback; Video: IVideo; Texture: TTexture;
  Data: array[0..8*8*3-1] of byte; Expected, Actual: TScreenPixels; I: integer;
begin
  ConsoleWriteLn('Testing menu drawing after libmpv rendering');
  for I:=0 to 63 do
  begin
    Data[I*3]:=(I mod 8)*32; Data[I*3+1]:=(I div 8)*32; Data[I*3+2]:=160;
  end;
  Texture:=Renderer.CreateTexture(@Data[0],PATH_NONE,8,8,TEXTURE_TYPE_PLAIN,false);
  Require(Texture<>nil,'cannot create the menu texture');
  try
    DrawMenu(Texture,Expected);
    Provider:=FindVideoProvider('MPV_Video');
    Require(Provider<>nil,'missing MPV provider');
    Require(Provider.Init,'cannot initialize MPV provider for the menu test');
    Video:=Provider.Open(Path(ParamStr(2)));
    Require(VideoClass(Video)='TVideo_MPV','the menu test opened '+VideoClass(Video));
    Video.Play;
    PumpVideo(Video,0,500,true);
    CheckVideoColors(0,'video before the menu');
    // Closing parks the player with its render target.
    Video:=nil;
    DrawMenu(Texture,Actual);
    RequireSamePixels(Expected,Actual,'menu after closing an MPV video');
    // Finalize frees the parked player and its target.
    Provider.Finalize;
    DrawMenu(Texture,Actual);
    RequireSamePixels(Expected,Actual,'menu after finalizing the MPV provider');
  finally
    Texture.Free;
  end;
  ConsoleWriteLn('PASS menu drawing after libmpv: unchanged after close and after finalize');
end;

procedure TestTwoPlayers;
var Provider: IVideoPlayback; First, Second: IVideo; Round: integer; Started, Elapsed: cardinal;
begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  Require(Provider.Init,'cannot initialize MPV provider for two players');
  ConsoleWriteLn('Testing two MPV players');
  for Round:=1 to 2 do
  begin
    // One adopts the parked player if there is one, the other creates its own.
    First:=Provider.Open(Path(ParamStr(2)));
    Second:=Provider.Open(Path(ParamStr(2)));
    Require(VideoClass(First)='TVideo_MPV','first of two opened '+VideoClass(First));
    Require(VideoClass(Second)='TVideo_MPV','second of two opened '+VideoClass(Second));
    First.Play;
    Second.SetPosition(2);
    Second.Play;
    Started:=SDL_GetTicks;
    repeat
      Elapsed:=SDL_GetTicks-Started;
      RenderVideo(First,Elapsed/1000);
      RenderVideo(Second,2+Elapsed/1000);
      SDL_PumpEvents;
      SDL_Delay(10);
    until Elapsed>=500;
    RenderVideo(First,Elapsed/1000);
    CheckVideoColors(0,'first of two players, round '+IntToStr(Round));
    RenderVideo(Second,2+Elapsed/1000);
    CheckVideoColors(2,'second of two players, round '+IntToStr(Round));
    if Round=1 then begin First:=nil; Second:=nil; end
    else begin Second:=nil; First:=nil; end;
    CheckError('two players closed, round '+IntToStr(Round));
  end;
  Provider.Finalize;
  CheckError('two players finalized');
  ConsoleWriteLn('PASS two MPV players: both play their own position, close in either order');
end;

// Report how long an open takes with a new player and with the player the
// previous video parked. An open returns once the first frame is in the video
// texture. Output only, no thresholds: software rendering says little about a
// GPU. The runner checks every label against the backend's own log line.
procedure TestOpenTimes;
var Provider: IVideoPlayback; Cycle: integer;

  // The video is a local, so it is closed, and its player parked, on return.
  procedure TimedOpen(const Name: string);
  var Video: IVideo; Started: UInt64;
  begin
    Started:=SDL_GetPerformanceCounter;
    Video:=Provider.Open(Path(ParamStr(2)));
    ConsoleWriteLn('OPEN-TIME '+Name+' '+
      IntToStr(Round((SDL_GetPerformanceCounter-Started)*1000/SDL_GetPerformanceFrequency)));
    Require(VideoClass(Video)='TVideo_MPV',Name+' open gave '+VideoClass(Video));
  end;

begin
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider');
  ConsoleWriteLn('Measuring video open times');
  for Cycle:=1 to 3 do
  begin
    // Finalize frees a parked player, so the next open creates one.
    Provider.Finalize;
    Require(Provider.Init,'cannot initialize MPV provider for open times');
    TimedOpen('fresh');
    TimedOpen('reused');
    TimedOpen('reused');
  end;
  Provider.Finalize;
  CheckError('open time measurement');
  ConsoleWriteLn('PASS open times measured');
end;

// A real failure after playback has started, not a decoder error or injected
// state: the .oversize fixture changes its display width to 81920 after 1.5 s,
// which no render target can hold.
procedure TestMidstreamRenderFailure;
var
  Provider: IVideoPlayback; Video: IVideo;
  LastFrame, CurrentFrame: TScreenPixels;
  Started, Elapsed: cardinal;
  I, Colored, Frames: integer;

  procedure Capture(out Pixels: TScreenPixels);
  begin
    Renderer.SetClearColor(0.5,0.5,0.5,1);
    Renderer.ClearFrameBuffer(CLEAR_COLOR);
    Video.Draw;
    glReadPixels(0,0,64,32,GL_RGBA,GL_UNSIGNED_BYTE,@Pixels[0]);
    CheckError('mid-stream failure draw');
  end;

begin
  ConsoleWriteLn('Testing real mid-stream render-target failure');
  Require(Renderer.MaxTextureSize<81920,
    'mid-stream fixture needs a maximum texture width below 81920');
  Provider:=FindVideoProvider('MPV_Video');
  Require(Provider<>nil,'missing MPV provider for mid-stream failure');
  Require(Provider.Init,'cannot initialize MPV for mid-stream failure');
  Video:=nil;
  try
    Video:=Provider.Open(Path(ParamStr(2)+'.oversize'));
    Require(VideoClass(Video)='TVideo_MPV','mid-stream fixture opened '+VideoClass(Video));
    Require(not Video.Finished,'mid-stream fixture was already finished at open');
    Capture(LastFrame);
    Colored:=0;
    for I:=0 to 64*32-1 do
      if (Abs(integer(LastFrame[I*4])-integer(LastFrame[I*4+1]))>80) or
         (Abs(integer(LastFrame[I*4+1])-integer(LastFrame[I*4+2]))>80) then Inc(Colored);
    Require(Colored>100,'mid-stream fixture has no decoded colored initial frame');
    Video.Play;
    Started:=SDL_GetTicks; Frames:=0;
    repeat
      Elapsed:=SDL_GetTicks-Started;
      Video.GetFrame(Elapsed/1000);
      if Video.Finished then Break;
      Capture(LastFrame);
      Inc(Frames);
      SDL_PumpEvents;
      SDL_Delay(10);
    until Elapsed>=5000;
    Require(Video.Finished,'mid-stream render-target failure did not finish within five seconds');
    Require(Frames>2,'mid-stream fixture failed before sustained playback');
    Capture(CurrentFrame);
    RequireSamePixels(LastFrame,CurrentFrame,'last frame after the mid-stream failure');
    // Calls after the terminal state must remain harmless and retain that image.
    Video.GetFrame(Elapsed/1000+1);
    Require(Video.Finished,'mid-stream failure stopped reporting Finished');
    Capture(CurrentFrame);
    RequireSamePixels(LastFrame,CurrentFrame,'image after a GetFrame that follows the failure');
  finally
    Video:=nil;
    Provider.Finalize;
  end;
  CheckError('mid-stream failure destruction');
  ConsoleWriteLn('PASS mid-stream render-target failure: Finished, last frame retained, safe drawing and destruction');
end;

// Run in a fresh process without a loadable libmpv: the MPV-enabled build
// must play files and snapshots through FFmpeg. The runner also requires
// exactly one missing-library warning, rather than one per open.
procedure TestMissingMpv;
var
  Saved: TProviderList;
  MpvProvider, FFmpegProvider: IVideoPlayback;
  Video: IVideo;
  I: integer;
begin
  ConsoleWriteLn('Testing missing libmpv fallback');
  KeepVideoProvidersOnly(Saved,FFmpegProvider,MpvProvider);
  try
    Ini.VideoBackend:='mpv';
    InitializeVideo;
    Require(VideoPlayback=MpvProvider,'missing-runtime selection did not choose the optional provider');
    for I:=1 to 2 do
    begin
      Video:=VideoPlayback.Open(Path(ParamStr(2)));
      Require(VideoClass(Video)='TVideo_FFmpeg','missing-runtime file opened '+VideoClass(Video));
      WaitFirstVideoFrame(Video,'missing-runtime file '+IntToStr(I));
      Video:=nil;
      CheckError('missing-runtime file closed');
    end;
    Video:=VideoPlayback.Open(Path(ParamStr(2)),ReadBytes(ParamStr(2)));
    Require(VideoClass(Video)='TVideo_FFmpeg','missing-runtime snapshot opened '+VideoClass(Video));
    WaitFirstVideoFrame(Video,'missing-runtime snapshot');
    Video.Play;
    PumpVideo(Video,0,1400,true);
    CheckVideoColors(1,'missing-runtime snapshot playback');
    Video:=nil;
    CheckError('missing-runtime snapshot closed');
  finally
    Video:=nil;
    RestoreProviders(Saved,MpvProvider);
  end;
  ConsoleWriteLn('PASS missing libmpv fallback: repeated files and an in-memory snapshot play through FFmpeg');
end;
{$ENDIF}

procedure Run;
var I: integer; Saved: array[0..3] of GLint; CaptureStarted: boolean;
begin
  SetDefaultNumericLocale;
  Log.SetLogLevel(LOG_LEVEL_INFO);
  Ini := TIni.Create;
  {$IFDEF UseMpvVideo}
  Ini.VideoBackend:='mpv';
  Ini.VideoHardwareDecoding:=ParamStr(3);
  if Ini.VideoHardwareDecoding='' then Ini.VideoHardwareDecoding:='no';
  {$ENDIF}
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
  if ParamStr(4)='missing-mpv' then
  begin
    {$IFDEF UseMpvVideo}
    TestMissingMpv;
    {$ELSE}
    raise Exception.Create('missing-runtime test needs an MPV-enabled build');
    {$ENDIF}
  end
  else
  begin
    Require(Renderer.CreateRenderTarget(0,32) = nil,'invalid target size accepted');
    Require(Renderer.CreateRenderTarget(Renderer.MaxTextureSize+1,32) = nil,'oversized target accepted');
    A := Renderer.CreateRenderTarget(64,32);
    Require(A <> nil,'render target unsupported');
    CheckError('target created');
    if Renderer is TRenderer_OpenGL2 then
    begin
      CaptureStarted := Renderer.BeginTextureCapture(A.Texture,64,32);
      if CaptureStarted then Renderer.EndTextureCapture;
      Require(not CaptureStarted,'legacy OpenGL unexpectedly enables menu-fade captures');
    end;
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
      {$IFDEF UseMpvVideo}
      // First, so that no video has drawn before the reference menu.
      TestMenuAfterVideo;
      {$ENDIF}
      TestVideoSelection;
      TestVideo('FFmpeg_Video');
      TestRetainedMenuVideo('FFmpeg_Video');
      {$IFDEF UseMpvVideo}
      TestVideo('MPV_Video');
      TestRetainedMenuVideo('MPV_Video');
      TestVideoStartup;
      TestVideoFallback;
      TestVideoWithoutFrame;
      TestMidstreamRenderFailure;
      TestVideoPreview;
      TestTwoPlayers;
      TestOpenTimes;
      {$ENDIF}
    end;
  end;
  Renderer.Free; Renderer:=nil;
  SDL_DestroyWindow(Screen); Screen:=nil; SDL_Quit;
  Ini.Free; Ini:=nil;
end;
begin
  try Run; except on E: Exception do begin ConsoleWriteLn(E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
