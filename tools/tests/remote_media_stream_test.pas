program remote_media_stream_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses Classes, SysUtils, URemoteMediaStream;
var Path: string; Output: TFileStream; Reader: TRemoteMediaStream; Data, Chunk: RawByteString; I: integer;
begin
 Path := GetTempFileName;
 try
  SetLength(Data, 70000);
  for I := 1 to Length(Data) do Data[I] := AnsiChar(I mod 251);
  Output := TFileStream.Create(Path, fmCreate);
  try Output.WriteBuffer(Data[1], Length(Data)); finally Output.Free; end;
  Reader := TRemoteMediaStream.Create(Path, 100, 40000);
  try
   Chunk := Reader.ReadChunk; Assert(Length(Chunk) = 32768);
   Assert(Chunk = Copy(Data, 101, 32768));
   Chunk := Reader.ReadChunk; Assert(Chunk = Copy(Data, 32869, 7133));
   Assert(Reader.Remaining = 0); Assert(Reader.ReadChunk = '');
  finally Reader.Free; end;
  try
   Reader := TRemoteMediaStream.Create(Path, 80000);
   Reader.Free; Assert(false);
  except on E: ERangeError do ; end;
 finally DeleteFile(Path); end;
 WriteLn('Bounded media range reads and invalid-range handling passed');
end.
