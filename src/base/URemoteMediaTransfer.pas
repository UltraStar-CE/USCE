{ One media transfer, advanced by its owning I/O scheduler. }
unit URemoteMediaTransfer;
{$mode Delphi}{$H+}
interface
uses SysUtils, fpjson, base64, URemoteMediaStream;
type
 TRemoteMediaTransfer = class
 private
  FReader: TRemoteMediaStream;
  FPending: TJSONObject;
  FRequestId: string;
  FStage: integer;
 public
  constructor Create(const RequestId, ResolvedPath, ContentType: string;
    RangeStart: int64 = 0; RangeEnd: int64 = -1);
  destructor Destroy; override;
  function Peek: TJSONObject;
  procedure Accepted;
  function Done: boolean;
 end;
implementation
constructor TRemoteMediaTransfer.Create(const RequestId, ResolvedPath, ContentType: string;
  RangeStart, RangeEnd: int64);
var Status: integer;
begin
 inherited Create;
 FRequestId := RequestId;
 FReader := TRemoteMediaStream.Create(ResolvedPath, RangeStart, RangeEnd);
 Status := 200;
 if (RangeStart <> 0) or (RangeEnd <> -1) then Status := 206;
 FPending := TJSONObject.Create(['type', 'song.preview.meta', 'requestId', RequestId,
   'statusCode', Status, 'contentType', ContentType, 'contentLength', FReader.Remaining]);
 if Status = 206 then FPending.Add('contentRange', Format('bytes %d-%d/%d',
   [FReader.Start, FReader.Start + FReader.Remaining - 1, FReader.Total]));
 FStage := 0;
end;
destructor TRemoteMediaTransfer.Destroy;
begin FPending.Free; FReader.Free; inherited; end;
function TRemoteMediaTransfer.Done: boolean;
begin Result := FStage = 3; end;
function TRemoteMediaTransfer.Peek: TJSONObject;
var Chunk: RawByteString;
begin
 if Done then Exit(nil);
 if FPending = nil then
 begin
  if FReader.Remaining > 0 then
  begin
   Chunk := FReader.ReadChunk;
   FPending := TJSONObject.Create(['type', 'song.preview.chunk', 'requestId', FRequestId,
     'data', EncodeStringBase64(Chunk)]);
  end
  else
  begin
   FStage := 2;
   FPending := TJSONObject.Create(['type', 'song.preview.end', 'requestId', FRequestId]);
  end;
 end;
 Result := FPending;
end;
procedure TRemoteMediaTransfer.Accepted;
begin
 if FPending = nil then Exit;
 FreeAndNil(FPending);
 if FStage = 0 then FStage := 1
 else if FStage = 2 then FStage := 3;
end;
end.
