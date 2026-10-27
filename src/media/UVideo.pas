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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/media/UVideo.pas $
 * $Id: UVideo.pas 3150 2015-10-20 00:07:57Z basisbit $
 *}

unit UVideo;

{*
 * based on 'An ffmpeg and SDL Tutorial' (http://www.dranger.com/ffmpeg/)
 *}

// uncomment if you want to see the debug stuff
{.$define DebugDisplay}
{.$define DebugFrames}
{.$define VideoBenchmark}
{.$define Info}

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

implementation

uses
  SysUtils,
  Math,
  ctypes,
  sdl2,
  avcodec,
  avformat,
  avutil,
  avio,
  rational,
  swscale,
  StrUtils,
  UMediaCore_FFmpeg,
  UCommon,
  UConfig,
  UIni,
  ULog,
  UMusic,
  UGraphicClasses,
  UGraphic,
  URenderer,
  UVideoPresenter,
  UPath;

{$IF DEFINED(cpuarm)}
    // RGBA asm was added with b32a42295ad7b254f9662082d799c0aae2071c2e
    // There are no RGB/BGR asm routines yet
    {$DEFINE PIXEL_FMT_32BITS}
{$ELSEIF DEFINED(cpuaarch64)}
    // RGBA asm was added with f1148390d7ed0444f3204d10277d09cc8d034e65
    // There are no RGB/BGR asm routines yet
    {$DEFINE PIXEL_FMT_32BITS}
{$ENDIF}

const
{$IFDEF PIXEL_FMT_32BITS}
  PIXEL_FMT_SIZE   = 4;
  PIXEL_FMT_FFMPEG = AV_PIX_FMT_RGBA;
  VIDEO_TEXTURE_TYP = TEXTURE_TYPE_TRANSPARENT;
{$ELSE}
  PIXEL_FMT_SIZE   = 3;
  PIXEL_FMT_FFMPEG = AV_PIX_FMT_RGB24;
  VIDEO_TEXTURE_TYP = TEXTURE_TYPE_PLAIN;
{$ENDIF}

  BUFFER_ALIGN = 32;

type
  IVideo_FFmpeg = interface (IVideo)
  ['{E640E130-C8C0-4399-AF02-67A3569313AB}']
    function Open(const FileName: IPath): boolean;
  end;

  TVideo_FFmpeg = class( TVideoPresenter, IVideo_FFmpeg )
  private
    fOpened: boolean;     //**< stream successfully opened
    fPaused: boolean;     //**< stream paused
    fEOF: boolean;        //**< end-of-file state

    fLoop: boolean;       //**< looping enabled

    fStream:        PAVStream;
    fStreamIndex :  integer;
    fFormatContext: PAVFormatContext;
    fCodecContext:  PAVCodecContext;
    fCodec:         PAVCodec;

    fAVFrame:     PAVFrame;
    fAVFrameRGB:  PAVFrame;

    fSwScaleContext: PSwsContext;

    fFrameDuration: extended; //**< duration of a video frame in seconds (= 1/fps)
    fFrameTime: extended; //**< video time position (absolute)
    fNextFrameTime: extended; //**< video time position (absolute)
    fLoopTime: extended;  //**< start time of the current loop
    fPreferDTS: boolean;

    procedure Reset();
    function DecodeFrame(): boolean;
    procedure SynchronizeTime(Frame: PAVFrame; pts: double);

    procedure ShowDebugInfo();

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
    procedure Draw(); override;
  end;

  TVideoPlayback_FFmpeg = class( TInterfacedObject, IVideoPlayback )
  private
    fInitialized: boolean;

  public
    function GetName: String;

    function Init(): boolean;
    function Finalize: boolean;

    function Open(const FileName : IPath): IVideo;
  end;

var
  FFmpegCore: TMediaCore_FFmpeg;
  PreferredCodecs: array of PAVCodec;
  PreferredCodecsParsed: boolean = false;

function IsSupportedScalingInput(Fmt: TAVPixelFormat): boolean;
begin
  Result := false;
  if sws_isSupportedInput(Fmt) > 0 then
    Result := true;
end;

function SelectFormat(CodecCtx: PAVCodecContext; Formats: PAVPixelFormat): TAVPixelFormat; cdecl;
begin
  while ord(Formats^) <> -1 do
  begin
    if IsSupportedScalingInput(Formats^) then
      break;
    Inc(Formats);
  end;
  Result := Formats^;
end;

function IsCodecUsable(Codec: PAVCodec): boolean;
var
  Fmt: PAVPixelFormat;
begin
  Result := true;
  if Codec^.type_ <> AVMEDIA_TYPE_VIDEO then
    Result := false;

  if Result and (
     av_codec_is_decoder(Codec) = 0
     ) then
    Result := false;

  if Result then
  begin
    {$IF LIBAVCODEC_VERSION_MAJOR >= 62}
    if (avcodec_get_supported_config(nil, codec, AV_CODEC_CONFIG_PIX_FORMAT, 0, @Fmt, nil) = 0) and (Fmt <> nil) then
    {$ELSE}
    Fmt := Codec^.pix_fmts;
    if (Fmt <> nil) then
    {$ENDIF}
    begin
      Result := false;
      // -1 is the value of AV_PIX_FMT_NONE, which terminates the pixel format list
      while ord(Fmt^) <> -1 do
      begin
        if IsSupportedScalingInput(Fmt^) then
        begin
          Result := true;
          break;
        end;
        Inc(Fmt);
      end;
    end;
  end;
end;

procedure ParsePreferredCodecs();
var
  I: integer;
  J: integer;
  NumCodecs: integer;
  ListCodecs: boolean;
  CodecName: ansistring;
  FormatDesc: PAVCodecDescriptor;
  FormatName: PAnsiChar;
  Codec: PAVCodec;
  Codec2: PAVCodec;
  CodecIterator: pointer;

const
  CodecDelims = [' ', ','];
begin
  ListCodecs := false;
  NumCodecs := WordCount(Ini.PreferredCodecNames, CodecDelims);
  SetLength(PreferredCodecs, NumCodecs);
  J := 0;
  for I := 1 to NumCodecs do
  begin
    CodecName := ExtractWord(I, Ini.PreferredCodecNames, CodecDelims);
    Codec := avcodec_find_decoder_by_name(PAnsiChar(CodecName));
    if Codec = nil then
    begin
      Log.LogError('Unknown preferred codec ' + CodecName, 'TVideo_FFmpeg');
      ListCodecs := true;
    end
    else if not IsCodecUsable(Codec) then
    begin
      Log.LogError('Can''t use ' + CodecName, 'TVideo_FFmpeg');
    end
    else
    begin
      PreferredCodecs[J] := Codec;
      Inc(J);
    end
  end;
  SetLength(PreferredCodecs, J);

  if ListCodecs then
  begin
    Log.LogInfo('Valid non-default codecs are:', 'TVideo_FFmpeg');
    CodecIterator := nil;
    Codec := av_codec_iterate(@CodecIterator);

    while Codec <> nil do
    begin
      if IsCodecUsable(Codec) then
      begin
        Codec2 := avcodec_find_decoder(Codec^.id);
        if strcomp(Codec2^.name, Codec^.name) <> 0 then
        begin
            FormatName := nil;
            FormatDesc := avcodec_descriptor_get(Codec^.id);
            if FormatDesc <> nil then
            begin
              FormatName := FormatDesc^.long_name;
              if FormatName = nil then
                FormatName := FormatDesc^.name;
            end;
            if FormatName <> nil then
              Log.LogInfo('    ' + Codec^.name, FormatName)
            else
              Log.LogInfo('    ' + Codec^.name, 'ID ' + inttostr(ord(Codec^.id)));
        end;
      end;
      Codec := av_codec_iterate(@CodecIterator);
    end;
  end;
  PreferredCodecsParsed := true;
end;


{*------------------------------------------------------------------------------
 * TVideoPlayback_ffmpeg
 *------------------------------------------------------------------------------}

function  TVideoPlayback_FFmpeg.GetName: String;
begin
  result := 'FFmpeg_Video';
end;

function TVideoPlayback_FFmpeg.Init(): boolean;
begin
  Result := true;

  if (fInitialized) then
    Exit;
  fInitialized := true;

  FFmpegCore := TMediaCore_FFmpeg.GetInstance();

end;

function TVideoPlayback_FFmpeg.Finalize(): boolean;
begin
  Result := true;
end;

function TVideoPlayback_FFmpeg.Open(const FileName : IPath): IVideo;
var
  Video: IVideo_FFmpeg;
begin
  Video := TVideo_FFmpeg.Create;
  if Video.Open(FileName) then
    Result := Video
  else
    Result := nil;
end;


{* TVideo_FFmpeg *}

constructor TVideo_FFmpeg.Create;
begin
  inherited Create;
  Reset();
end;

destructor TVideo_FFmpeg.Destroy;
begin
  Close();
  inherited Destroy;
end;

function TVideo_FFmpeg.Open(const FileName : IPath): boolean;
var
  errnum: Integer;
  AudioStreamIndex: integer;
  r_frame_rate: cdouble;
  PossibleCodecs: array of PAVCodec;
  CodecID: TAVCodecID;

  function ReduceSize: boolean;
  var
    tex, scale: ^cardinal;
  begin
    Result := false;
    if fTexWidth >= fAspect * fTexHeight then
    begin
      tex := @fTexWidth;
      scale := @fScaledWidth;
    end
    else
    begin
      tex := @fTexHeight;
      scale := @fScaledHeight;
    end;
    if tex^ > 64 then
    begin
      tex^ := 1 shl BsrDWord(tex^ - 1);
      scale^ := tex^;
      Result := true;
    end;
  end;

begin
  Result := false;
  Reset();

  FFmpegCore.LockAVCodec();
  if not PreferredCodecsParsed then
    ParsePreferredCodecs;
  FFmpegCore.UnlockAVCodec();

  // use custom 'ufile' protocol for UTF-8 support
  errnum := FFmpegCore.AVFormatOpenInput(@fFormatContext, PAnsiChar(UTF8ToAnsi(FileName.ToUTF8)));//'ufile:'+FileName.ToUTF8));
  if (errnum <> 0) then
  begin
    Log.LogError('Failed to open file "'+ FileName.ToNative +'" ('+FFmpegCore.GetErrorString(errnum)+'::'+IntToStr(errnum)+')');
    Exit;
  end;

  // update video info
  errnum := avformat_find_stream_info(fFormatContext, nil);
  if (errnum < 0) then
  begin
    Log.LogError('No stream info found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  // find video stream
  FFmpegCore.FindStreamIDs(fFormatContext, fStreamIndex, AudioStreamIndex);
  if (fStreamIndex < 0) then
  begin
    Log.LogError('No video stream found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;
  Log.LogInfo('VideoStreamIndex : ' + inttostr(fStreamIndex), 'TVideoPlayback_ffmpeg.Open');

  fStream := PPAVStream(PtrUInt(fFormatContext^.streams) + fStreamIndex * Sizeof(pointer))^;
{$IF LIBAVFORMAT_VERSION < 59000000}
  CodecID := fStream^.codec^.codec_id;
{$ELSE}
  CodecID := fStream^.codecpar^.codec_id;
{$ENDIF}

  fPreferDTS := false;
  // workaround for FFmpeg bug #6560
  if (LeftStr(fFormatContext^.iformat^.name, 4) = 'mov,') or (fFormatContext^.iformat^.name = 'mov') then
    fPreferDTS := true;

  SetLength(PossibleCodecs, 1);
  for fCodec in PreferredCodecs do
    if fCodec^.id = CodecID then
    begin
      PossibleCodecs[High(PossibleCodecs)] := fCodec;
      SetLength(PossibleCodecs, Length(PossibleCodecs) + 1);
    end;
  PossibleCodecs[High(PossibleCodecs)] := avcodec_find_decoder(CodecID);

  errnum := -1;
  for fCodec in PossibleCodecs do
  begin
    if fCodec = nil then
      continue;

    fCodecContext := FFmpegCore.GetCodecContext(fStream, fCodec);
    if fCodecContext = nil then
      continue;

    fCodecContext^.get_format := @SelectFormat;

    // set debug options
    fCodecContext^.debug := 0;

    // detect bug-workarounds automatically
    fCodecContext^.workaround_bugs := FF_BUG_AUTODETECT;
    // error resilience strategy (careful/compliant/agressive/very_aggressive)
    //fCodecContext^.error_resilience := FF_ER_CAREFUL; //FF_ER_COMPLIANT;
    // allow non spec compliant speedup tricks.

    //fCodecContext^.flags2 := CODEC_FLAG2_FAST;

    // Note: avcodec_open() and avcodec_close() are not thread-safe and will
    // fail if called concurrently by different threads.
    FFmpegCore.LockAVCodec();
    try
        // by setting this explicitly to 0, it won't default to a single thread
        fCodecContext^.thread_count := 0;

        errnum := avcodec_open2(fCodecContext, fCodec, nil);
    finally
      FFmpegCore.UnlockAVCodec();
    end;
    if errnum >= 0 then
      Break;
    Log.LogError('Error ' + IntToStr(errnum) + ' returned by ' + fCodec^.name, 'TVideoPlayback_ffmpeg.Open');
    {$IF LIBAVFORMAT_VERSION >= 59000000}
    avcodec_free_context(@fCodecContext);
    {$ENDIF}
  end;
  if (errnum < 0) then
  begin
    Log.LogError('No matching codec found', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end
  else
    Log.LogInfo('Using ' + fCodec^.name + ' codec', 'TVideoPlayback_ffmpeg.Open');

  {$ifdef DebugDisplay}
  DebugWriteln('Found a matching Codec: '+ fCodecContext^.Codec.Name + sLineBreak +
    sLineBreak +
    '  Width = '+inttostr(fCodecContext^.width) +
    ', Height='+inttostr(fCodecContext^.height) + sLineBreak +
    '  Aspect    : '+inttostr(fCodecContext^.sample_aspect_ratio.num) + '/' +
                     inttostr(fCodecContext^.sample_aspect_ratio.den) + sLineBreak +
    '  Framerate : '+inttostr(fCodecContext^.framerate.num) + '/' +
                     inttostr(fCodecContext^.framerate.den));
  {$endif}

  // calculate some information for video display
  fAspect := av_q2d(fCodecContext^.sample_aspect_ratio);
  if (fAspect = 0) then
    fAspect := fCodecContext^.width /
               fCodecContext^.height
  else
    fAspect := fAspect * fCodecContext^.width /
                         fCodecContext^.height;

  r_frame_rate := av_q2d(fStream^.r_frame_rate);

  fFrameDuration := 1/r_frame_rate;

  // hack to get reasonable framerate (for divx and others)
  if (fFrameDuration < 0.02) then // 0.02 <-> 50 fps
  begin
    fFrameDuration := r_frame_rate;
    while (fFrameDuration > 50) do
      fFrameDuration := fFrameDuration/10;
    fFrameDuration := 1/fFrameDuration;
  end;

  Log.LogInfo('Framerate: '+inttostr(floor(1/fFrameDuration))+'fps', 'TVideoPlayback_ffmpeg.Open');

  fTexWidth   := fCodecContext^.width;
  fTexHeight  := fCodecContext^.height;
  fScaledWidth := fCodecContext^.width;
  fScaledHeight := fCodecContext^.height;
  while (Max(fTexWidth, fTexHeight) > Renderer.MaxTextureSize) do
  begin
    if not ReduceSize() then
    begin
      Log.LogError('Failed to create video texture', 'TVideoPlayback_ffmpeg.Open');
      Close();
      Exit;
    end;
  end;
  FreeAndNil(fFrameTex);
  fFrameTex := Renderer.CreateTexture(nil, PATH_NONE, fTexWidth, fTexHeight, VIDEO_TEXTURE_TYP, false);

  // allocate space for decoded frame and rgb frame
  fAVFrame := av_frame_alloc();
  fAVFrameRGB := av_frame_alloc();
  if ((fAVFrame = nil) or (fAVFrameRGB = nil)) then
  begin
    Log.LogError('Failed to allocate buffers', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  errnum := av_image_alloc(@fAVFrameRGB^.data[0], @fAVFrameRGB^.linesize[0],
                           (fScaledWidth + BUFFER_ALIGN - 1) and -BUFFER_ALIGN, fScaledHeight,
                           PIXEL_FMT_FFMPEG, BUFFER_ALIGN);
  if (errnum < 0) then
  begin
    Log.LogError('av_image_alloc failed: ' + FFmpegCore.GetErrorString(errnum), 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  // if available get a SWScale-context -> faster than the deprecated img_convert().
  // SWScale has accelerated support for PIX_FMT_RGB32/PIX_FMT_BGR24/PIX_FMT_BGR565/PIX_FMT_BGR555.
  // Note: PIX_FMT_RGB32 is a BGR- and not an RGB-format (maybe a bug)!!!
  // The BGR565-formats (GL_UNSIGNED_SHORT_5_6_5) is way too slow because of its
  // bad OpenGL support. The BGR formats have MMX(2) implementations but no speed-up
  // could be observed in comparison to the RGB versions.
  fSwScaleContext := sws_getContext(
      fCodecContext^.width, fCodecContext^.height,
      fCodecContext^.pix_fmt,
      fScaledWidth, fScaledHeight,
      PIXEL_FMT_FFMPEG,
      SWS_FAST_BILINEAR, nil, nil, nil);
  if (fSwScaleContext = nil) then
  begin
    Log.LogError('Failed to get swscale context', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  fOpened := true;
  Result := true;
end;

procedure TVideo_FFmpeg.Reset();
begin
  // close previously opened video
  Close();

  fOpened := False;
  fPaused := False;
  fFrameDuration := 0;
  fFrameTime := 0;
  fNextFrameTime := 0;
  fStream := nil;
  fStreamIndex := -1;
  fFrameTexValid := false;

  fEOF := false;

  fLoop := false;
  fLoopTime := 0;

  ResetPresentation;
end;

procedure TVideo_FFmpeg.Close;
begin
  if assigned(fAVFrameRGB) then
    av_freep(@fAVFrameRGB^.data[0]);
  av_freep(@fAVFrameRGB);
  av_frame_free(@fAVFrame);

  if (fCodecContext <> nil) then
  begin
    // avcodec_close() is not thread-safe
    FFmpegCore.LockAVCodec();
    try
      {$IF LIBAVFORMAT_VERSION < 59000000)}
      avcodec_close(fCodecContext);
      {$ELSE}
      avcodec_free_context(@fCodecContext);
      {$ENDIF}
    finally
      FFmpegCore.UnlockAVCodec();
    end;
  end;

  if (fFormatContext <> nil) then
    FFmpegCore.AVFormatCloseInput(@fFormatContext);

  {$IF LIBAVFORMAT_VERSION < 59000000)}
  fCodecContext  := nil;
  {$ENDIF}
  fFormatContext := nil;

  sws_freeContext(fSwScaleContext);

  FreeAndNil(fFrameTex);
  fOpened := False;
end;

procedure TVideo_FFmpeg.SynchronizeTime(Frame: PAVFrame; pts: double);
var
  FrameDelay: double;
begin
  fFrameTime := fNextFrameTime;
  if (pts <> 0) then
  begin
    // if we have pts, set video clock to it
    fFrameTime := pts;
  end;
  // update the video clock
  if fCodecContext^.framerate.num = 0 then
    FrameDelay := 0.04
  else
    FrameDelay := av_q2d(av_inv_q(fCodecContext^.framerate));
  // if we are repeating a frame, adjust clock accordingly
  FrameDelay := FrameDelay + Frame^.repeat_pict * (FrameDelay * 0.5);
  fNextFrameTime := fFrameTime + FrameDelay;
end;

{**
 * Decode a new frame from the video stream.
 * The decoded frame is stored in fAVFrame. fFrameTime is updated to the new frame's
 * time.
 * @param pts will be updated to the presentation time of the decoded frame.
 * returns true if a frame could be decoded. False if an error or EOF occured.
 *}
function TVideo_FFmpeg.DecodeFrame(): boolean;
var
  FrameFinished: Integer;
  pbIOCtx: PAVIOContext;
  errnum: integer;
  AVPacket: PAVPacket;
  pts: int64;
  dts: int64;
  fileSize: int64;
  urlError: integer;
begin
  Result := false;
  FrameFinished := 0;
  AVPacket := nil;

  if fEOF then
    Exit;

  // read packets until we have a finished frame (or there are no more packets)
  while (FrameFinished = 0) do
  begin
    errnum := avcodec_receive_frame(fCodecContext, fAVFrame);
    if errnum = 0 then
      Break;
    if errnum = AVERROR_EOF then
    begin
      fEOF := true;
      Exit;
    end;
    if errnum <> AVERROR(EAGAIN) then
      Continue;

    if (AVPacket = nil) then
      AVPacket := av_packet_alloc();
    errnum := av_read_frame(fFormatContext, AVPacket);
    if (errnum < 0) then
    begin
      // failed to read a frame, check reason

      pbIOCtx := fFormatContext^.pb;

      // check for end-of-file (EOF is not an error)
      if (avio_feof(pbIOCtx) <> 0) then
      begin
        avcodec_send_packet(fCodecContext, nil);
        Continue;
      end;

      // check for errors
      urlError := pbIOCtx^.error;
      if (urlError <> 0) then
      begin
        Log.LogError('Video decoding file error', 'TVideoPlayback_FFmpeg.DecodeFrame');
        av_packet_free(@AVPacket);
        Exit;
      end;

      // url_feof() does not detect an EOF for some mov-files (e.g. deluxe.mov)
      // so we have to do it this way.
      fileSize := avio_size(fFormatContext^.pb);
      if (((fileSize <> 0) and (pbIOCtx^.pos >= fileSize))
          or (errnum = AVERROR_EOF)) then // LIBAVFORMAT_VERSION >= 56000000 tells us if EOF reached.
      begin
        avcodec_send_packet(fCodecContext, nil);
        Continue;
      end;

      // error occured, log and exit
      Log.LogError('Video decoding error: ' + IntToStr(errnum), 'TVideoPlayback_FFmpeg.DecodeFrame');
      av_packet_free(@AVPacket);
      Exit;
    end;

    // if we got a packet from the video stream, then decode it
    if (AVPacket^.stream_index = fStreamIndex) then
    begin

      // decode packet
      avcodec_send_packet(fCodecContext, AVPacket);

    end;

    // free the packet from av_read_frame
    av_packet_free(@AVPacket);
  end;

  // reset opaque data and update pts
  pts := fAVFrame^.pts;
  dts := fAVFrame^.pkt_dts;

  if (pts = AV_NOPTS_VALUE) or (fPreferDTS and (dts <> AV_NOPTS_VALUE)) then
    pts := dts;

  if pts = AV_NOPTS_VALUE then
    pts := 0
  else if fStream^.start_time <> AV_NOPTS_VALUE then
    pts := pts - fStream^.start_time;

  // synchronize time on each complete frame
  SynchronizeTime(fAVFrame, pts * av_q2d(fStream^.time_base));

  Result := true;
end;

procedure TVideo_FFmpeg.GetFrame(Time: Extended);
var
  errnum: Integer;
  CurrentTime: Extended;
  TimeDiff: Extended;
  DropFrameCount: Integer;
  i: Integer;
  Success: boolean;
const
  SKIP_FRAME_DIFF = 0.010; // start skipping if we are >= 10ms too late
begin
  if not fOpened then
    Exit;

  if fPaused then
    Exit;

  {*
   * Synchronization - begin
   *}

  // requested stream position (relative to the last loop's start)
  if (fLoop) then
    CurrentTime := Time - fLoopTime
  else
    CurrentTime := Time;

  // check if current texture still contains the active frame
  if (fFrameTexValid) then
  begin
    // time since the last frame was returned
    TimeDiff := CurrentTime - fFrameTime;

    {$IFDEF DebugDisplay}
    DebugWriteln('Time:      '+inttostr(floor(Time*1000)) + sLineBreak +
                 'VideoTime: '+inttostr(floor(fFrameTime*1000)) + sLineBreak +
                 'TimeBase:  '+inttostr(floor(fFrameDuration*1000)) + sLineBreak +
                 'TimeDiff:  '+inttostr(floor(TimeDifference*1000)));
    {$endif}

    // check if time has reached the next frame
    if (TimeDiff < fFrameDuration) then
    begin
      {$ifdef DebugFrames}
      // frame delay debug display
      GoldenRec.Spawn(200,15,1,16,0,-1,ColoredStar,$00ff00);
      {$endif}

      {$IFDEF DebugDisplay}
      DebugWriteln('not getting new frame' + sLineBreak +
          'Time:      '+inttostr(floor(Time*1000)) + sLineBreak +
          'VideoTime: '+inttostr(floor(fFrameTime*1000)) + sLineBreak +
          'TimeBase:  '+inttostr(floor(fFrameDuration*1000)) + sLineBreak +
          'TimeDiff:  '+inttostr(floor(TimeDifference*1000)));
      {$endif}

      // we do not need a new frame now
      Exit;
    end;
  end;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkStart(15);
  {$ENDIF}

  // fetch new frame (updates fFrameTime)
  Success := DecodeFrame();
  TimeDiff := CurrentTime - fFrameTime;

  // check if we have to skip frames
  // Either if we are one frame behind or if the skip threshold has been reached.
  // Do not skip if the difference is less than fFrameDuration as there is no next frame.
  // Note: We assume that fFrameDuration is the length of one frame.
  if (TimeDiff >= Max(fFrameDuration, SKIP_FRAME_DIFF)) then
  begin
    {$IFDEF DebugFrames}
    //frame drop debug display
    GoldenRec.Spawn(200,55,1,16,0,-1,ColoredStar,$ff0000);
    {$ENDIF}
    {$IFDEF DebugDisplay}
    DebugWriteln('skipping frames' + sLineBreak +
        'TimeBase:  '+inttostr(floor(fFrameDuration*1000)) + sLineBreak +
        'TimeDiff:  '+inttostr(floor(TimeDifference*1000)));
    {$endif}

    // update video-time
    DropFrameCount := Trunc(TimeDiff / fFrameDuration);
    fFrameTime := fFrameTime + DropFrameCount*fFrameDuration;

    // skip frames
    for i := 1 to DropFrameCount do
      Success := DecodeFrame();
  end;

  // check if we got an EOF or error
  if (not Success) then
  begin
    if fLoop then
    begin
      // we have to loop, so rewind
      SetPosition(0);
      // record the start-time of the current loop, so we can
      // determine the position in the stream (fFrameTime-fLoopTime) later.
      fLoopTime := Time;
    end;
    Exit;
  end;

  {*
   * Synchronization - end
   *}

  // TODO: support for pan&scan
  //if (fAVFrame.pan_scan <> nil) then
  //begin
  //  Writeln(Format('PanScan: %d/%d', [fAVFrame.pan_scan.width, fAVFrame.pan_scan.height]));
  //end;

  // otherwise we convert the pixeldata from YUV to RGB
  try

  errnum := sws_scale(fSwScaleContext, @fAVFrame.data, @fAVFrame.linesize,
          0, fCodecContext^.Height,
          @fAVFrameRGB.data, @fAVFrameRGB.linesize);
  except
    ;
  end;

  {$IF LIBSWSCALE_VERSION < 8003000}
  {$IF DEFINED(CPUX86_64) or DEFINED(CPUX86)}
  // Unscaled conversion with libswscale lacked the emms instruction.
  // With FFmpeg 7.1 these mmx(ext) implementations have been removed.
  // I assume you won't run this game on an x86 system that does not yet support mmx.
  asm
    emms
  end ['st(0)','st(1)','st(2)','st(3)','st(4)','st(5)','st(6)','st(7)',
       'mm0','mm1','mm2','mm3','mm4','mm5','mm6','mm7'];
  {$ENDIF}
  {$ENDIF}

  if (errnum < 0) then
  begin
    Log.LogError('Image conversion failed', 'TVideoPlayback_ffmpeg.GetFrame');
    Exit;
  end;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(15);
  Log.BenchmarkStart(16);
  {$ENDIF}

  fFrameTex.UpdateData(fAVFrameRGB^.data[0], fScaledWidth, fScaledHeight, fAVFrameRGB.linesize[0] div PIXEL_FMT_SIZE, VIDEO_TEXTURE_TYP);
  if (not fFrameTexValid) then
    fFrameTexValid := true;

  {$ifdef DebugFrames}
  //frame decode debug display
  GoldenRec.Spawn(200, 35, 1, 16, 0, -1, ColoredStar, $ffff00);
  {$endif}

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(16);
  Log.LogBenchmark('FFmpeg', 15);
  Log.LogBenchmark('Texture', 16);
  {$ENDIF}
end;

procedure TVideo_FFmpeg.Draw();
begin
  if (not fOpened) then
    Exit;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkStart(15);
  {$ENDIF}

  inherited Draw();

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(15);
  Log.LogBenchmark('Draw', 15);
  {$ENDIF}

  {$IF Defined(Info) or Defined(DebugFrames)}
  ShowDebugInfo();
  {$IFEND}
end;

procedure TVideo_FFmpeg.ShowDebugInfo();
begin
  {$IFDEF Info}
  if (fFrameTime+fFrameDuration < 0) then
  begin
    SetFontFamily(0);
    SetFontStyle(1);
    SetFontItalic(False);
    SetFontSize(27);
    SetFontColor(0.7, 1, 0.3, 1);
    SetFontPos (300, 0);
    PrintText('Delay due to negative VideoGap');
  end;
  {$ENDIF}

  {$IFDEF DebugFrames}
    Renderer.DrawQuad(0, 0, 0, 250, 70, 0, 0, 0, 0.2);
    SetFontFamily(0);
    SetFontStyle(1);
    SetFontItalic(False);
    SetFontSize(27);
    SetFontColor(1, 1, 1, 1);
    SetFontPos (5, 0);
    PrintText('delaying frame');
    SetFontPos (5, 20);
    PrintText('fetching frame');
    SetFontPos (5, 40);
    PrintText('dropping frame');
  {$ENDIF}
end;

procedure TVideo_FFmpeg.Play;
begin
end;

procedure TVideo_FFmpeg.Pause;
begin
  fPaused := not fPaused;
end;

procedure TVideo_FFmpeg.Stop;
begin
end;

procedure TVideo_FFmpeg.SetLoop(Enable: boolean);
begin
  fLoop := Enable;
  fLoopTime := 0;
end;

function TVideo_FFmpeg.GetLoop(): boolean;
begin
  Result := fLoop;
end;

{**
 * Sets the stream's position.
 * The stream is set to the first keyframe with timestamp <= Time.
 * Note that fFrameTime is set to Time no matter if the actual position seeked to is
 * at Time or the time of a preceding keyframe. fFrameTime will be updated to the
 * actual frame time when GetFrame() is called the next time.
 * @param Time new position in seconds
 *}
procedure TVideo_FFmpeg.SetPosition(Time: real);
var
  SeekFlags: integer;
begin
  if not fOpened then
    Exit;

  if (Time < 0) then
    Time := 0;

  // TODO: handle fLoop-times
  //Time := Time mod VideoDuration;

  // Do not use the AVSEEK_FLAG_ANY here. It will seek to any frame, even
  // non keyframes (P-/B-frames). It will produce corrupted video frames as
  // FFmpeg does not use the information of the preceding I-frame.
  // The picture might be gray or green until the next keyframe occurs.
  // Instead seek the first keyframe smaller than the requested time
  // (AVSEEK_FLAG_BACKWARD). As this can be some seconds earlier than the
  // requested time, let the sync in GetFrame() do its job.
  SeekFlags := AVSEEK_FLAG_BACKWARD;

  fFrameTime := Time;
  fNextFrameTime := Time;
  fEOF := false;
  fFrameTexValid := false;

  if (av_seek_frame(fFormatContext,
     fStreamIndex,
     Round(Time / av_q2d(fStream^.time_base)),
     SeekFlags) < 0) then
  begin
      Log.LogError('av_seek_frame() failed', 'TVideoPlayback_ffmpeg.SetPosition');
      Exit;
  end;

  avcodec_flush_buffers(fCodecContext);
end;

function  TVideo_FFmpeg.GetPosition: real;
begin
  Result := fFrameTime;
end;



initialization
  MediaManager.Add(TVideoPlayback_FFmpeg.Create);

end.
