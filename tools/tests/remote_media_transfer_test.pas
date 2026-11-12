program remote_media_transfer_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses Classes, SysUtils, fpjson, base64, URemoteMediaTransfer;
var Path: string; Stream: TFileStream; Transfer: TRemoteMediaTransfer;
 Data, Received: RawByteString; Message: TJSONObject;
begin
 Path := GetTempFileName;
 try
  Data := StringOfChar('x', 70000);
  Stream := TFileStream.Create(Path, fmCreate);
  try Stream.WriteBuffer(Data[1], Length(Data)); finally Stream.Free; end;
  Transfer := TRemoteMediaTransfer.Create('test', Path, 'audio/wav');
  try
   Message := Transfer.Peek;
   Assert(Message.Get('type', '') = 'song.preview.meta');
   Assert(Transfer.Peek = Message); Transfer.Accepted;
   Received := '';
   while not Transfer.Done do
   begin
    Message := Transfer.Peek;
    Assert(Transfer.Peek = Message);
    if Message.Get('type', '') = 'song.preview.chunk' then
     Received := Received + DecodeStringBase64(Message.Get('data', ''));
    Transfer.Accepted;
   end;
   Assert(Received = Data);
   Assert(Transfer.Peek = nil);
  finally Transfer.Free; end;
 finally DeleteFile(Path); end;
 WriteLn('Media transfer retries preserve chunks and complete exactly once');
end.
