program BackgroundVideoTest;
{$mode Delphi}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils, SDL2, UIni, UPath, URenderer,
  UVideo, UMusic, UMediaCore_FFmpeg;

type
  TCaptureTexture = class(TTexture)
    procedure UpdateData(Data: PByte; Width, Height: word; PixelsPerRow: integer; Typ: TTextureType); override;
    procedure Release; override;
  end;
  TCaptureRenderer = class(TRenderer)
    constructor Create;
    function LoadTexture(Data: PByte; W, H: integer; const Identifier: IPath;
      Typ: TTextureType; UseMipmaps: boolean): TTexture; override;
  end;
var
  Owner: TThreadID;
  Updates, Red, Green, Blue: integer;
  V: IVideo;
  P: IVideoPlayback;
  I, BeforePause: integer;
  Start: cardinal;

procedure Check(Value: boolean; const Msg: string);
begin
  if not Value then raise Exception.Create(Msg);
end;
procedure TCaptureTexture.Release;
begin end;
procedure TCaptureTexture.UpdateData(Data: PByte; Width, Height: word;
  PixelsPerRow: integer; Typ: TTextureType);
begin
  Check(SDL_ThreadID = Owner, 'texture upload left the main thread');
  Red := Data[0]; Green := Data[1]; Blue := Data[2]; Inc(Updates);
end;
constructor TCaptureRenderer.Create;
begin inherited; fMaxTextureSize := 4096; end;
function TCaptureRenderer.LoadTexture(Data: PByte; W, H: integer;
  const Identifier: IPath; Typ: TTextureType; UseMipmaps: boolean): TTexture;
begin Result := TCaptureTexture.Create(Identifier); end;

procedure AwaitColor(Time: double; Color: integer);
var Deadline: cardinal; Match: boolean;
begin
  Deadline := SDL_GetTicks + 2000;
  repeat
    V.GetFrame(Time);
    Match := ((Color = 0) and (Red > 200) and (Green < 40) and (Blue < 40)) or
      ((Color = 1) and (Green > 200) and (Red < 40) and (Blue < 40)) or
      ((Color = 2) and (Blue > 200) and (Green < 40) and (Red < 40));
    if Match then Exit;
    SDL_Delay(2);
  until SDL_GetTicks >= Deadline;
  raise Exception.Create('Expected color was not delivered at ' + FloatToStr(Time));
end;

begin
  SDL_Init(0); Owner := SDL_ThreadID;
  Ini := TIni(TIni.NewInstance);
  Renderer := TCaptureRenderer.Create;
  InitializeVideo; P := VideoPlayback;
  for I := 1 to 5 do
  begin
    Red := 0; Green := 0; Blue := 0;
    V := P.Open(Path(ParamStr(1))); Check(V <> nil, 'fixture did not open');
    V.Play; AwaitColor(0.2, 0);
    V.Pause; BeforePause := Updates;
    V.GetFrame(1.2); SDL_Delay(20); V.GetFrame(1.2);
    Check(Updates = BeforePause, 'paused video uploaded a frame');
    V.Pause; V.SetPosition(1.2); AwaitColor(1.2, 1);
    // Replace pending seeks before decoding catches up; only the last wins.
    V.SetPosition(0.2); V.SetPosition(2.2); AwaitColor(2.2, 2);
    V.SetPosition(0.2); AwaitColor(0.2, 0);
    V.GetFrame(1.2); AwaitColor(1.2, 1);
    V.GetFrame(2.2); AwaitColor(2.2, 2);
    V.Loop := true;
    // Drain EOF and allow the asynchronous rewind to deliver a new red frame.
    Start := SDL_GetTicks;
    repeat V.GetFrame(3.2); SDL_Delay(2);
    until (Red > 200) or (SDL_GetTicks - Start > 2000);
    Check(Red > 200, 'loop did not restart');
    Start := SDL_GetTicks; V := nil;
    Check(SDL_GetTicks - Start < 2000, 'decoder close did not join promptly');
  end;
  V := P.Open(Path(ParamStr(2))); Check(V <> nil, 'slow fixture did not open');
  V.SetPosition(2.1); AwaitColor(2.1, 2); V.Loop := true;
  // An exhausted queue must not truncate the final frame's display interval.
  for I := 1 to 25 do
  begin
    V.GetFrame(2.2); SDL_Delay(2);
    Check(Blue > 200, 'loop restarted before the final frame duration elapsed');
  end;
  Start := SDL_GetTicks;
  repeat V.GetFrame(3.0); SDL_Delay(2);
  until (Red > 200) or (SDL_GetTicks - Start > 2000);
  Check(Red > 200, 'loop did not restart after final-frame duration');
  V := nil;
  WriteLn('PASS: main-thread uploads, pause, seek generations, backward seek, EOF loop, final-frame duration and repeated close');
  P := nil; Renderer.Free; Renderer := nil;
end.
