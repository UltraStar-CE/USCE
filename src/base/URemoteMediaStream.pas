{ Bounded reads of game-resolved media paths. Single I/O-thread ownership.
  Network requests must resolve song IDs before constructing this reader. }
unit URemoteMediaStream;
{$mode Delphi}{$H+}
interface
uses Classes, SysUtils;
type
 TRemoteMediaStream = class
 private
  FStream: THandleStream;
  FHandle: THandle;
  FRemaining, FStart, FTotal: int64;
 public
  constructor Create(const ResolvedPath: string; RangeStart: int64 = 0; RangeEnd: int64 = -1);
  destructor Destroy; override;
  function ReadChunk: RawByteString;
  property Remaining: int64 read FRemaining;
  property Start: int64 read FStart;
  property Total: int64 read FTotal;
 end;
implementation
{$IFDEF MSWINDOWS}uses Windows;{$ENDIF}
constructor TRemoteMediaStream.Create(const ResolvedPath: string; RangeStart, RangeEnd: int64);
begin
 inherited Create;
 FHandle := THandle(-1);
 if (RangeStart < 0) or (RangeEnd < -1) then raise ERangeError.Create('invalid_media_range');
 {$IFDEF MSWINDOWS}
 FHandle := CreateFileW(PWideChar(UTF8Decode(ResolvedPath)), GENERIC_READ,
   FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
   FILE_ATTRIBUTE_NORMAL, 0);
 {$ELSE}
 FHandle := FileOpen(ResolvedPath, fmOpenRead or fmShareDenyNone);
 {$ENDIF}
 if FHandle = THandle(-1) then raise EFOpenError.Create('cannot_open_media');
 FStream := THandleStream.Create(FHandle);
 FTotal := FStream.Size;
 if (RangeStart > FTotal) or ((RangeStart = FTotal) and (FTotal <> 0)) then
  raise ERangeError.Create('invalid_media_range');
 if RangeEnd = -1 then RangeEnd := FTotal - 1;
 if RangeEnd >= FTotal then RangeEnd := FTotal - 1;
 if (FTotal > 0) and (RangeEnd < RangeStart) then raise ERangeError.Create('invalid_media_range');
 FStart := RangeStart;
 FRemaining := RangeEnd - RangeStart + 1;
 FStream.Position := RangeStart;
end;
destructor TRemoteMediaStream.Destroy;
begin
 FStream.Free;
 if FHandle <> THandle(-1) then FileClose(FHandle);
 inherited;
end;
function TRemoteMediaStream.ReadChunk: RawByteString;
var Amount, Received: integer;
begin
 Result := '';
 if FRemaining <= 0 then Exit;
 if FRemaining > 32768 then Amount := 32768 else Amount := integer(FRemaining);
 SetLength(Result, Amount);
 Received := FStream.Read(Result[1], Amount);
 if Received <> Amount then raise EReadError.Create('media_changed_during_transfer');
 Dec(FRemaining, Received);
end;
end.
