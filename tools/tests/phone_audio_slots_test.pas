program phone_audio_slots_test;
{$mode Delphi}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}SysUtils, base64, UPhoneAudio;
var Samples: array[0..9599] of smallint;
function Packet(Value: smallint): string;
var Bytes: RawByteString; I: integer;
  procedure Put32(Offset: integer; Value: cardinal);
  var J: integer;
  begin for J:=0 to 3 do Bytes[Offset+J+1]:=AnsiChar((Value shr (J*8)) and 255); end;
begin
  SetLength(Bytes,980); FillChar(Bytes[1],980,0);
  Bytes[1]:='U'; Bytes[2]:='A'; Bytes[3]:='P'; Bytes[4]:='1';
  Put32(4,1); Put32(8,48000); Put32(12,480);
  for I:=0 to 479 do Move(Value, Bytes[21+I*2],2);
  Result:=EncodeStringBase64(Bytes);
end;
procedure SendPcm(Slot: integer; const Who: string; Value: smallint);
begin PhoneAudio.Signal(UTF8String(Format('{"type":"audio.pcm","slot":%d,"playerId":"%s","pcm":"%s"}',[Slot,Who,Packet(Value)]))); end;
begin
  if not PhoneAudio.Start('ipc://','',ParamStr(1)) then raise Exception.Create(PhoneAudio.LastError);
  try
    PhoneAudio.Signal('{"type":"remote.players.snapshot","players":[{"playerId":"one","slot":1},{"playerId":"two","slot":2}]}');
    SendPcm(1,'one',4000); SendPcm(2,'two',8000);
    if PhoneAudio.Poll(@Samples[0],Length(Samples),0)<>480 then raise Exception.Create('Mic 1 missing');
    if Samples[0]<>4000 then raise Exception.Create('Mic 1 mixed with another lane');
    if PhoneAudio.Poll(@Samples[0],Length(Samples),1)<>480 then raise Exception.Create('Mic 2 missing');
    if Samples[0]<>8000 then raise Exception.Create('Mic 2 mixed with another lane');
    PhoneAudio.Signal('{"type":"remote.players.snapshot","players":[{"playerId":"two","slot":1}]}');
    SendPcm(2,'two',12000); SendPcm(1,'two',16000);
    if PhoneAudio.Poll(@Samples[0],Length(Samples),1)<>0 then raise Exception.Create('Old Mic 2 retained moved audio');
    if PhoneAudio.Poll(@Samples[0],Length(Samples),0)<>480 then raise Exception.Create('Moved phone lost fresh sequence');
    if Samples[0]<>16000 then raise Exception.Create('Moved phone has stale audio');
    WriteLn('PASS: Pascal routing isolates Mic 1/Mic 2 and resets audio on slot changes');
  finally PhoneAudio.Stop; end;
end.
