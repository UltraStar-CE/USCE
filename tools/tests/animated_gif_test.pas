program GifCheck;
{$mode Delphi}
uses UIni, SysUtils, UPath, URenderer, UVideo, UMusic, UMediaCore_FFmpeg,
 UMenuBackgroundTexture, UMenuBackgroundVideo;
type TCaptureTexture=class(TTexture)
 procedure UpdateData(Data:PByte;Width,Height:word;PixelsPerRow:integer;Typ:TTextureType);override;
 procedure Release;override;
 end;
 TCaptureRenderer=class(TRenderer)
 constructor Create;
 function LoadTexture(Data:PByte;W,H:integer;const Identifier:IPath;Typ:TTextureType;UseMipmaps:boolean):TTexture;override;
 end;
var R,B,Updates,RedFrames,BlueFrames:integer; V:IVideo; P:IVideoPlayback;I:integer;Found:boolean;
procedure Check(Value:boolean;const M:string);begin if not Value then raise Exception.Create(M);end;
procedure TCaptureTexture.Release;begin end;
procedure TCaptureTexture.UpdateData(Data:PByte;Width,Height:word;PixelsPerRow:integer;Typ:TTextureType);
begin R:=Data[0];B:=Data[2];Inc(Updates);if R>B then Inc(RedFrames);if B>R then Inc(BlueFrames);end;
constructor TCaptureRenderer.Create;begin inherited;fMaxTextureSize:=4096;end;
function TCaptureRenderer.LoadTexture(Data:PByte;W,H:integer;const Identifier:IPath;Typ:TTextureType;UseMipmaps:boolean):TTexture;
begin Result:=TCaptureTexture.Create(Identifier);end;
begin
 Found:=false;for I:=Low(SUPPORTED_EXTS_BACKGROUNDTEXTURE) to High(SUPPORTED_EXTS_BACKGROUNDTEXTURE) do if SUPPORTED_EXTS_BACKGROUNDTEXTURE[I]='.gif' then Found:=true;
 Check(not Found,'GIF must not select the static texture route');
 Found:=false;for I:=Low(SUPPORTED_EXTS_BACKGROUNDVIDEO) to High(SUPPORTED_EXTS_BACKGROUNDVIDEO) do if SUPPORTED_EXTS_BACKGROUNDVIDEO[I]='.gif' then Found:=true;
 Check(Found,'GIF video route');
 Ini:=TIni(TIni.NewInstance);Renderer:=TCaptureRenderer.Create;InitializeVideo;P:=VideoPlayback;
 V:=P.Open(Path(ParamStr(1)));Check(V<>nil,'GIF opens in actual game decoder');V.Loop:=true;V.Play;
 for I:=0 to 200 do V.GetFrame(I*0.05);
 Check(RedFrames>2,'red frames recur');Check(BlueFrames>2,'blue frames recur');
 Writeln('PASS: actual game FFmpeg decoder updates RGB texture: ',RedFrames,' red / ',BlueFrames,' blue across 10 seconds');
 V:=nil;P:=nil;Renderer.Free;Renderer:=nil;
end.
