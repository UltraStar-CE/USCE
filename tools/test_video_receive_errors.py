"""Run the production receive loop with deterministic FFmpeg failure injection."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class VideoReceiveErrorTests(unittest.TestCase):
    def test_persistent_error_returns_once_and_preserves_eagain_and_eof(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        source = (Path(__file__).resolve().parents[1] / 'src/media/UVideo.pas').read_text()
        loop = source.split('function TVideo_FFmpeg.DecodeFrame(): boolean;', 1)[1]
        loop = loop.split('  // reset opaque data and update pts', 1)[0]
        harness = r'''program ReceiveErrors;
{$mode delphi}
uses SysUtils;
type
  TInt64 = record pos: int64; error: integer; end;
  PAVIOContext = ^TInt64;
  TFormat = record pb: PAVIOContext; end;
  PFormat = ^TFormat;
  TPacket = record stream_index: integer; end;
  PAVPacket = ^TPacket;
  PPAVPacket = ^PAVPacket;
  TLogger = class procedure LogError(const Msg, Context: string); end;
  TVideo_FFmpeg = class
    fEOF, fDecodeFailed: boolean;
    fCodecContext, fAVFrame: pointer;
    fFormatContext: PFormat;
    fStreamIndex: integer;
    function DecodeFrame: boolean;
  end;
const EAGAIN = 11; AVERROR_EOF = -100;
var Scenario, Calls, Reads, Frees, LivePackets, Errors: integer;
    Log: TLogger;
function AVERROR(Value: integer): integer; begin Result := -Value; end;
procedure TLogger.LogError(const Msg, Context: string);
begin Inc(Errors); end;
function avcodec_receive_frame(C, F: pointer): integer;
begin
  Inc(Calls);
  if Calls > 4 then raise Exception.Create('receive loop made no progress');
  case Scenario of
    0: Result := 0;
    1: if Calls = 1 then Result := AVERROR(EAGAIN) else Result := 0;
    2: Result := AVERROR_EOF;
    else Result := -99;
  end;
end;
function av_packet_alloc: PAVPacket;
begin New(Result); Result^.stream_index := 0; Inc(LivePackets); end;
procedure av_packet_free(P: PPAVPacket);
begin
  if P^ <> nil then begin Dispose(P^); P^ := nil; Inc(Frees); Dec(LivePackets); end;
end;
function av_read_frame(F: PFormat; P: PAVPacket): integer;
begin Inc(Reads); Result := 0; end;
procedure avcodec_send_packet(C: pointer; P: PAVPacket); begin end;
function avio_feof(P: PAVIOContext): integer; begin Result := 0; end;
function avio_size(P: PAVIOContext): int64; begin Result := 100; end;
function TVideo_FFmpeg.DecodeFrame: boolean;
''' + loop + r'''
  Result := true;
end;
procedure Check(Value: boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var V: TVideo_FFmpeg;
begin
  Log := TLogger.Create;
  for Scenario := 0 to 3 do
  begin
    Calls := 0; Reads := 0; Frees := 0; Errors := 0;
    V := TVideo_FFmpeg.Create;
    if Scenario < 2 then Check(V.DecodeFrame, 'ordinary frame rejected')
    else Check(not V.DecodeFrame, 'error accepted');
    Check(LivePackets = 0, 'packet leaked');
    if Scenario = 1 then Check((Reads = 1) and (Frees = 1), 'EAGAIN did not advance');
    if Scenario = 2 then Check(V.fEOF and (Errors = 0), 'EOF reported as failure');
    if Scenario = 3 then
    begin
      Check(V.fEOF and V.fDecodeFailed and (Errors = 1), 'failure state missing');
      Check(not V.DecodeFrame, 'terminal stream retried');
      Check((Calls = 1) and (Errors = 1), 'persistent failure retried or logged again');
    end;
    V.Free;
  end;
  Log.Free;
  WriteLn('PASS: normal frame, EAGAIN, EOF, persistent error, packet ownership');
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receive_errors.pas'
            path.write_bytes(harness.encode())
            result = subprocess.run([compiler, '-Mdelphi', '-Ciro', str(path)], cwd=directory,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))],
                           check=True, timeout=5)
