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

  // Decoded (RGB) frames are prepared ahead of time by a background thread.
  // The queue length is derived from this memory budget so that 1080p videos
  // get about half a second of buffer (enough to ride out slow disk reads,
  // e.g. from an external HDD) while 4K videos do not use excessive memory.
  VIDEO_QUEUE_BYTES = 128 * 1024 * 1024;
  VIDEO_QUEUE_MIN_FRAMES = 3;
  VIDEO_QUEUE_MAX_FRAMES = 16;
  // While the decoder is behind schedule it skips the RGB conversion of frames
  // that would never be shown. To keep the picture moving even when the
  // decoder cannot keep up at all, one frame is still converted after this
  // many consecutive skipped frames.
  VIDEO_MAX_CONSECUTIVE_DROPS = 15;

type
  IVideo_FFmpeg = interface (IVideo)
  ['{E640E130-C8C0-4399-AF02-67A3569313AB}']
    function Open(const FileName: IPath; const Media: TBytes = nil): boolean;
  end;

  // A converted frame waiting in the queue
  TVideoFrameSlot = record
    Data:     array[0..3] of pcuint8;
    Linesize: array[0..3] of cint;
    Time:     extended; //**< presentation time of the frame (stream time)
  end;

  TVideo_FFmpeg = class( TVideoPresenter, IVideo_FFmpeg )
  private
    fOpened: boolean;     //**< stream successfully opened
    fPaused: boolean;     //**< stream paused
    fDecodeFailed: boolean; // terminal decoder error (worker only)
    fEOF: boolean;        //**< end-of-file state of the decoder (decode thread only)

    {*
     * Background decoding.
     * The decode thread owns fFormatContext, fCodecContext, fAVFrame,
     * fSwScaleContext and the fDec* clock. The main thread only uploads
     * finished frames from the queue to the texture. Everything below that is
     * accessed by both threads is protected by fLock.
     *}
    fDecodeThread: PSDL_Thread;
    fLock:         PSDL_Mutex;
    fWakeCond:     PSDL_Cond;  //**< wakes the decode thread (free slot, seek, quit)
    fQuit:         boolean;    //**< decode thread must terminate
    fSeekPending:  boolean;    //**< decode thread must seek to fSeekTime
    fSeekTime:     extended;
    fSeekGen:      integer;    //**< incremented on each seek to discard stale frames
    fRequestedTime: extended;  //**< stream time the main thread is currently displaying
    fDecoderFailed: boolean; // published terminal failure, protected by fLock
    fDecoderEOF:   boolean;    //**< decode thread reached the end of the stream
    fFinished:     boolean;    //**< presentation has reached the end (main thread)
    fSlots:        array of TVideoFrameSlot; //**< ring buffer of converted frames
    fSlotHead:     integer;    //**< index of the oldest queued frame
    fSlotCount:    integer;    //**< number of queued frames
    fDecFrameTime: extended;     //**< time of the last decoded frame (decode thread only)
    fDecNextFrameTime: extended; //**< expected time of the next frame (decode thread only)
    fDecSeekTarget: extended;    //**< time of the last seek (decode thread only)
    fTexHasContent: boolean;   //**< texture was filled at least once

    fLoop: boolean;       //**< looping enabled

    fStream:        PAVStream;
    fStreamIndex :  integer;
    fFormatContext: PAVFormatContext;
    fCodecContext:  PAVCodecContext;
    fCodec:         PAVCodec;

    fAVFrame:     PAVFrame;

    fSwScaleContext: PSwsContext;
    fSwsColorSpace: integer; //**< frame colorspace last passed to swscale, -1: none yet (decode thread only)
    fSwsColorRange: integer; //**< frame color range last passed to swscale, -1: none yet (decode thread only)

    fFrameDuration: extended; //**< duration of a video frame in seconds (= 1/fps)
    fFrameTime: extended; //**< time of the frame in the texture (main thread)
    fLoopTime: extended;  //**< start time of the current loop
    fPreferDTS: boolean;

    procedure Reset();
    function DecodeFrame(): boolean;
    procedure SynchronizeTime(Frame: PAVFrame; pts: double);
    procedure UpdateColorspace(Frame: PAVFrame);

    function AllocSlots(): boolean;
    procedure FreeSlots();
    function StartDecodeThread(): boolean;
    procedure StopDecodeThread();
    procedure DecodeLoop();
    procedure DoSeek(Time: extended);

    procedure ShowDebugInfo();

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
    procedure Draw(); override;
  end;

  TVideoPlayback_FFmpeg = class( TInterfacedObject, IVideoPlayback )
  private
    fInitialized: boolean;

  public
    function GetName: String;

    function Init(): boolean;
    function Finalize: boolean;

    function Open(const FileName : IPath; const Media: TBytes = nil): IVideo;
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

function TVideoPlayback_FFmpeg.Open(const FileName : IPath; const Media: TBytes = nil): IVideo;
var
  Video: IVideo_FFmpeg;
begin
  Video := TVideo_FFmpeg.Create;
  if Video.Open(FileName, Media) then
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

function TVideo_FFmpeg.Open(const FileName : IPath; const Media: TBytes = nil): boolean;
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
  errnum := FFmpegCore.AVFormatOpenInput(@fFormatContext, PAnsiChar(FileName.ToUTF8), Media);
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

  fAVFrame := av_frame_alloc();
  if (fAVFrame = nil) then
  begin
    Log.LogError('Failed to allocate buffers', 'TVideoPlayback_ffmpeg.Open');
    Close();
    Exit;
  end;

  if not AllocSlots() then
  begin
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
  // the colorspace details are set from the first decoded frame
  fSwsColorSpace := -1;
  fSwsColorRange := -1;

  fOpened := true;
  if not StartDecodeThread() then
  begin
    Close();
    Exit;
  end;
  Result := true;
end;

{**
 * Allocates the ring buffer of converted frames. The number of slots depends
 * on the frame size (see VIDEO_QUEUE_BYTES).
 *}
function TVideo_FFmpeg.AllocSlots(): boolean;
var
  I, NumSlots, errnum: integer;
  FrameBytes: int64;
begin
  Result := false;

  FrameBytes := int64((fScaledWidth + BUFFER_ALIGN - 1) and -BUFFER_ALIGN) *
                fScaledHeight * PIXEL_FMT_SIZE;
  if FrameBytes <= 0 then
    FrameBytes := 1;
  NumSlots := EnsureRange(VIDEO_QUEUE_BYTES div FrameBytes,
                          VIDEO_QUEUE_MIN_FRAMES, VIDEO_QUEUE_MAX_FRAMES);

  SetLength(fSlots, NumSlots);
  for I := 0 to High(fSlots) do
    FillChar(fSlots[I], SizeOf(TVideoFrameSlot), 0);

  for I := 0 to High(fSlots) do
  begin
    errnum := av_image_alloc(@fSlots[I].Data[0], @fSlots[I].Linesize[0],
                             (fScaledWidth + BUFFER_ALIGN - 1) and -BUFFER_ALIGN, fScaledHeight,
                             PIXEL_FMT_FFMPEG, BUFFER_ALIGN);
    if (errnum < 0) then
    begin
      Log.LogError('av_image_alloc failed: ' + FFmpegCore.GetErrorString(errnum), 'TVideoPlayback_ffmpeg.Open');
      Exit;
    end;
  end;

  fSlotHead := 0;
  fSlotCount := 0;
  Log.LogInfo('Video queue: ' + IntToStr(NumSlots) + ' frames', 'TVideoPlayback_ffmpeg.Open');
  Result := true;
end;

procedure TVideo_FFmpeg.FreeSlots();
var
  I: integer;
begin
  for I := 0 to High(fSlots) do
    av_freep(@fSlots[I].Data[0]);
  SetLength(fSlots, 0);
  fSlotHead := 0;
  fSlotCount := 0;
end;

function VideoDecodeThreadMain(Data: Pointer): integer; cdecl;
begin
  try
    TVideo_FFmpeg(Data).DecodeLoop();
  except
    on E: Exception do
    begin
      Log.LogError('Video decode thread: ' + E.Message, 'VideoDecodeThreadMain');
      with TVideo_FFmpeg(Data) do
      begin
        // DecodeLoop releases its mutex in its finally block.
        SDL_LockMutex(fLock);
        try
          fDecoderFailed := true;
          fDecoderEOF := true;
        finally
          SDL_UnlockMutex(fLock);
        end;
      end;
    end;
  end;
  Result := 0;
end;

function TVideo_FFmpeg.StartDecodeThread(): boolean;
begin
  fQuit := false;
  fSeekPending := false;
  fDecoderEOF := false;
  fDecoderFailed := false;
  fLock := SDL_CreateMutex();
  fWakeCond := SDL_CreateCond();
  Result := false;
  if (fLock = nil) or (fWakeCond = nil) then
  begin
    Log.LogError('Could not create video decode synchronization: ' + SDL_GetError(), 'TVideoPlayback_ffmpeg.Open');
    Exit;
  end;
  fDecodeThread := SDL_CreateThread(@VideoDecodeThreadMain, 'USCE video decoder', Self);
  if (fDecodeThread = nil) then
    Log.LogError('Could not create video decode thread: ' + SDL_GetError(), 'TVideoPlayback_ffmpeg.Open');
  Result := fDecodeThread <> nil;
end;

procedure TVideo_FFmpeg.StopDecodeThread();
begin
  if (fDecodeThread <> nil) then
  begin
    SDL_LockMutex(fLock);
    fQuit := true;
    SDL_CondBroadcast(fWakeCond);
    SDL_UnlockMutex(fLock);
    SDL_WaitThread(fDecodeThread, nil);
    fDecodeThread := nil;
  end;

  if (fWakeCond <> nil) then
    SDL_DestroyCond(fWakeCond);
  fWakeCond := nil;
  if (fLock <> nil) then
    SDL_DestroyMutex(fLock);
  fLock := nil;
end;

{**
 * Main loop of the decode thread: keeps the queue filled with converted frames.
 * Reading from disk, decoding and the YUV->RGB conversion all happen here so a
 * slow disk access or an expensive frame never blocks rendering.
 *}
procedure TVideo_FFmpeg.DecodeLoop();
var
  Gen: integer;
  Slot: integer;
  SeekTo: extended;
  FrameTime: extended;
  Success: boolean;
  Stale: boolean;
  Drops: integer;
  errnum: integer;
  LockHeld: boolean;
begin
  Drops := 0;
  SDL_LockMutex(fLock);
  LockHeld := true;
  try
    while not fQuit do
    begin
      if fSeekPending then
      begin
        fSeekPending := false;
        SeekTo := fSeekTime;
        LockHeld := false;
        SDL_UnlockMutex(fLock);
        DoSeek(SeekTo);
        Drops := 0;
        SDL_LockMutex(fLock);
        LockHeld := true;
        Continue;
      end;

      if (fSlotCount >= Length(fSlots)) or fDecoderEOF then
      begin
        SDL_CondWait(fWakeCond, fLock);
        Continue;
      end;

      Gen := fSeekGen;
      LockHeld := false;
      SDL_UnlockMutex(fLock);

      Success := DecodeFrame();
      FrameTime := fDecFrameTime;

      SDL_LockMutex(fLock);
      LockHeld := true;
      if (Gen <> fSeekGen) or fQuit then
        Continue; // a seek was requested meanwhile, this frame is obsolete
      if not Success then
      begin
        fDecoderFailed := fDecodeFailed;
        fDecoderEOF := true;
        Continue;
      end;

      // Skip the conversion of frames that are already too late to be shown
      // (e.g. after seeking to a keyframe before the requested position, or if
      // the decoder fell behind). A queued frame is never newer than this one,
      // so this does not change which frame ends up on screen.
      // Frames before the seek target are always skipped, otherwise at most
      // VIDEO_MAX_CONSECUTIVE_DROPS in a row so the picture keeps moving.
      Stale := (FrameTime + fFrameDuration <= fRequestedTime) and
               ((FrameTime + fFrameDuration <= fDecSeekTarget) or
                (Drops < VIDEO_MAX_CONSECUTIVE_DROPS));
      if Stale then
      begin
        Inc(Drops);
        Continue;
      end;
      Drops := 0;

      // Only the decode thread writes to the slot behind the queue's tail,
      // the main thread only reads queued slots, so no lock is needed here.
      Slot := (fSlotHead + fSlotCount) mod Length(fSlots);
      LockHeld := false;
      SDL_UnlockMutex(fLock);

      UpdateColorspace(fAVFrame);
      errnum := -1;
      try
        errnum := sws_scale(fSwScaleContext, @fAVFrame.data, @fAVFrame.linesize,
                0, fCodecContext^.Height,
                @fSlots[Slot].Data[0], @fSlots[Slot].Linesize[0]);
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

      SDL_LockMutex(fLock);
      LockHeld := true;
      if (errnum < 0) then
      begin
        Log.LogError('Image conversion failed', 'TVideoPlayback_ffmpeg.DecodeLoop');
        Continue;
      end;
      if (Gen = fSeekGen) and not fQuit then
      begin
        fSlots[Slot].Time := FrameTime;
        Inc(fSlotCount);
      end;
    end;
  finally
    if LockHeld then SDL_UnlockMutex(fLock);
  end;
end;

{**
 * Seeks the stream (decode thread only).
 * The stream is set to the first keyframe with timestamp <= Time, frames
 * before Time are then skipped by DecodeLoop().
 *}
procedure TVideo_FFmpeg.DoSeek(Time: extended);
begin
  fDecSeekTarget := Time;
  fDecFrameTime := Time;
  fDecNextFrameTime := Time;
  fEOF := false;
  fDecodeFailed := false;

  // Do not use the AVSEEK_FLAG_ANY here. It will seek to any frame, even
  // non keyframes (P-/B-frames). It will produce corrupted video frames as
  // FFmpeg does not use the information of the preceding I-frame.
  // The picture might be gray or green until the next keyframe occurs.
  // Instead seek the first keyframe smaller than the requested time
  // (AVSEEK_FLAG_BACKWARD). As this can be some seconds earlier than the
  // requested time, let DecodeLoop() skip the frames before it.
  if (av_seek_frame(fFormatContext,
     fStreamIndex,
     Round(Time / av_q2d(fStream^.time_base)),
     AVSEEK_FLAG_BACKWARD) < 0) then
  begin
    Log.LogError('av_seek_frame() failed', 'TVideoPlayback_ffmpeg.DoSeek');
    Exit;
  end;

  avcodec_flush_buffers(fCodecContext);
end;

procedure TVideo_FFmpeg.Reset();
begin
  // close previously opened video
  Close();

  fOpened := False;
  fPaused := False;
  fFrameDuration := 0;
  fFrameTime := 0;
  fStream := nil;
  fStreamIndex := -1;
  fFrameTexValid := false;
  fTexHasContent := false;

  fEOF := false;
  fDecodeFailed := false;
  fDecoderEOF := false;
  fDecoderFailed := false;
  fDecFrameTime := 0;
  fDecNextFrameTime := 0;
  fDecSeekTarget := 0;
  fRequestedTime := 0;
  fSeekPending := false;
  fSeekGen := 0;

  fLoop := false;
  fFinished := false;
  fLoopTime := 0;

  ResetPresentation;
end;

procedure TVideo_FFmpeg.Close;
begin
  // the decode thread uses the contexts freed below
  StopDecodeThread();

  FreeSlots();
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
  fSwScaleContext := nil;

  FreeAndNil(fFrameTex);
  fOpened := False;
end;

procedure TVideo_FFmpeg.SynchronizeTime(Frame: PAVFrame; pts: double);
var
  FrameDelay: double;
begin
  fDecFrameTime := fDecNextFrameTime;
  if (pts <> 0) then
  begin
    // if we have pts, set video clock to it
    fDecFrameTime := pts;
  end;
  // update the video clock
  if fCodecContext^.framerate.num = 0 then
    FrameDelay := 0.04
  else
    FrameDelay := av_q2d(av_inv_q(fCodecContext^.framerate));
  // if we are repeating a frame, adjust clock accordingly
  FrameDelay := FrameDelay + Frame^.repeat_pict * (FrameDelay * 0.5);
  fDecNextFrameTime := fDecFrameTime + FrameDelay;
end;

{**
 * Sets the YUV->RGB matrix and the input range swscale uses for Frame
 * (decode thread only).
 * Without this swscale converts every frame as limited range BT.601, which
 * shifts the colours of BT.709 (HD) and full range videos.
 * swscale is only reconfigured if the frame's tags differ from the last frame.
 *}
procedure TVideo_FFmpeg.UpdateColorspace(Frame: PAVFrame);
var
  SwsColorSpace: cint;
  SrcRange: cint;
begin
  if (Frame^.colorspace = fSwsColorSpace) and
     (Frame^.color_range = fSwsColorRange) then
    Exit;
  fSwsColorSpace := Frame^.colorspace;
  fSwsColorRange := Frame^.color_range;

  case Frame^.colorspace of
    AVCOL_SPC_BT709:     SwsColorSpace := SWS_CS_ITU709;
    AVCOL_SPC_BT470BG:   SwsColorSpace := SWS_CS_ITU601;
    AVCOL_SPC_SMPTE170M: SwsColorSpace := SWS_CS_SMPTE170M;
    AVCOL_SPC_SMPTE240M: SwsColorSpace := SWS_CS_SMPTE240M;
    AVCOL_SPC_FCC:       SwsColorSpace := SWS_CS_FCC;
    AVCOL_SPC_BT2020_NCL,
    AVCOL_SPC_BT2020_CL: SwsColorSpace := SWS_CS_BT2020;
    else
    begin
      // Untagged or not supported by swscale: guess from the frame size the
      // way mpv does, BT.709 from 1280 pixels width or above 576 lines,
      // BT.601 below.
      if (fCodecContext^.width >= 1280) or (fCodecContext^.height > 576) then
        SwsColorSpace := SWS_CS_ITU709
      else
        SwsColorSpace := SWS_CS_ITU601;
    end;
  end;

  // An untagged range is treated as limited, as swscale did so far. The
  // decoders that output the deprecated full range YUVJ formats (MJPEG, full
  // range H.264) tag their frames with AVCOL_RANGE_JPEG.
  if (Frame^.color_range = AVCOL_RANGE_JPEG) then
    SrcRange := 1
  else
    SrcRange := 0;

  // RGB output is full range; brightness, contrast and saturation keep
  // swscale's defaults (16.16 fixed point). A failure is only logged,
  // playback continues.
  if (sws_setColorspaceDetails(fSwScaleContext,
        sws_getCoefficients(SwsColorSpace), SrcRange,
        sws_getCoefficients(SWS_CS_DEFAULT), 1,
        0, 1 shl 16, 1 shl 16) < 0) then
    Log.LogError('Failed to set colorspace details', 'TVideoPlayback_ffmpeg.UpdateColorspace')
  else
    Log.LogInfo(Format('Colorspace %d, color range %d: swscale colorspace %d, source range %d',
                       [Frame^.colorspace, Frame^.color_range, SwsColorSpace, SrcRange]),
                'TVideoPlayback_ffmpeg.UpdateColorspace');
end;

{**
 * Decode a new frame from the video stream (decode thread only).
 * The decoded frame is stored in fAVFrame. fDecFrameTime is updated to the new
 * frame's time.
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
    begin
      Log.LogError('Video frame receive error: ' + IntToStr(errnum), 'TVideoPlayback_FFmpeg.DecodeFrame');
      fEOF := true;
      fDecodeFailed := true;
      av_packet_free(@AVPacket);
      Exit;
    end;

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
  CurrentTime: Extended;
  Slot: integer;
  SlotTime: Extended;
  Freed: boolean;
  ReachedEnd, DecodeFailed: boolean;
begin
  if not fOpened then
    Exit;

  if fPaused then
    Exit;

  if (fDecodeThread = nil) then
    Exit;

  // requested stream position (relative to the last loop's start)
  if (fLoop) then
    CurrentTime := Time - fLoopTime
  else
    CurrentTime := Time;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkStart(15);
  {$ENDIF}

  Slot := -1;
  SlotTime := 0;
  Freed := false;

  SDL_LockMutex(fLock);
  fRequestedTime := CurrentTime;

  // drop queued frames that have already been superseded by a newer one
  while (fSlotCount > 1) and
        (fSlots[(fSlotHead + 1) mod Length(fSlots)].Time <= CurrentTime) do
  begin
    {$IFDEF DebugFrames}
    //frame drop debug display
    GoldenRec.Spawn(200,55,1,16,0,-1,ColoredStar,$ff0000);
    {$ENDIF}
    fSlotHead := (fSlotHead + 1) mod Length(fSlots);
    Dec(fSlotCount);
    Freed := true;
  end;

  // show the oldest queued frame once its time has come. If the texture does
  // not contain a valid frame yet (after opening or seeking), show the first
  // available frame right away.
  if (fSlotCount > 0) and
     ((fSlots[fSlotHead].Time <= CurrentTime) or (not fFrameTexValid)) then
  begin
    Slot := fSlotHead;
    SlotTime := fSlots[Slot].Time;
  end;

  ReachedEnd := (fSlotCount = 0) and fDecoderEOF;
  DecodeFailed := fDecoderFailed;

  if Freed then
    SDL_CondSignal(fWakeCond);
  SDL_UnlockMutex(fLock);

  if (Slot >= 0) then
  begin
    // The decode thread does not touch queued slots, so the upload can be
    // done without holding the lock.
    fFrameTex.UpdateData(fSlots[Slot].Data[0], fScaledWidth, fScaledHeight,
                         fSlots[Slot].Linesize[0] div PIXEL_FMT_SIZE, VIDEO_TEXTURE_TYP);
    fFrameTime := SlotTime;
    fFrameTexValid := true;
    fTexHasContent := true;

    {$ifdef DebugFrames}
    //frame decode debug display
    GoldenRec.Spawn(200, 35, 1, 16, 0, -1, ColoredStar, $ffff00);
    {$endif}

    SDL_LockMutex(fLock);
    if (fSlotCount > 0) and (fSlotHead = Slot) then
    begin
      fSlotHead := (fSlotHead + 1) mod Length(fSlots);
      Dec(fSlotCount);
      SDL_CondSignal(fWakeCond);
    end;
    SDL_UnlockMutex(fLock);
  end
  else if ReachedEnd and (DecodeFailed or not fFrameTexValid or
          (CurrentTime >= fFrameTime + fFrameDuration)) then
  begin
    if fLoop and not DecodeFailed and fFrameTexValid then
    begin
      SetPosition(0);
      fLoopTime := Time;
    end
    else
      fFinished := true;
  end;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkEnd(15);
  Log.LogBenchmark('Texture', 15);
  {$ENDIF}
end;

function TVideo_FFmpeg.Finished: boolean;
begin
  Result := fFinished;
end;

procedure TVideo_FFmpeg.Draw();
begin
  if (not fOpened) then
    Exit;

  {$IFDEF VideoBenchmark}
  Log.BenchmarkStart(15);
  {$ENDIF}

  if fTexHasContent then
    inherited Draw()
  else
    // the first frame is not decoded yet: draw black instead of an empty texture
    DrawBlack();

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
 * The seek itself is done asynchronously by the decode thread (see DoSeek()):
 * the stream is set to the first keyframe with timestamp <= Time and the frames
 * before Time are skipped. Until the first frame at the new position is ready
 * the last frame stays on screen.
 * Note that fFrameTime is set to Time no matter if the actual position seeked to is
 * at Time or the time of a preceding keyframe. fFrameTime will be updated to the
 * actual frame time when GetFrame() shows the next frame.
 * @param Time new position in seconds
 *}
procedure TVideo_FFmpeg.SetPosition(Time: real);
begin
  if not fOpened then
    Exit;

  if (Time < 0) then
    Time := 0;

  // TODO: handle fLoop-times
  //Time := Time mod VideoDuration;

  fFrameTime := Time;
  fFrameTexValid := false;
  fFinished := false;

  if (fLock = nil) then
    Exit;

  SDL_LockMutex(fLock);
  Inc(fSeekGen);
  fSeekPending := true;
  fSeekTime := Time;
  fRequestedTime := Time;
  fSlotCount := 0;
  fDecoderEOF := false;
  fDecoderFailed := false;
  SDL_CondSignal(fWakeCond);
  SDL_UnlockMutex(fLock);
end;

function  TVideo_FFmpeg.GetPosition: real;
begin
  Result := fFrameTime;
end;



initialization
  MediaManager.Add(TVideoPlayback_FFmpeg.Create);

end.
