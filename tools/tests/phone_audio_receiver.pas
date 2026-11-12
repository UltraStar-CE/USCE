program phone_audio_receiver;
{$mode Delphi}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, UPhoneAudio;
var Receiver: TPhoneAudio;
    Samples: array[0..9599] of smallint;
    Count: integer;
    Total, Started, NextReport: QWord;
begin
  Receiver := TPhoneAudio.Create;
  try
    if not Receiver.Start(UTF8String(GetEnvironmentVariable('USCE_RAW_AUDIO_RELAY')),
      UTF8String(GetEnvironmentVariable('USCE_RAW_AUDIO_ICE')),
      GetEnvironmentVariable('USCE_RAW_AUDIO_LIBRARY')) then
    begin
      WriteLn(Receiver.LastError);
      Halt(1);
    end;
    Total := 0;
    Started := GetTickCount64;
    NextReport := Started;
    while GetTickCount64 - Started < 120000 do
    begin
      Count := Receiver.Poll(@Samples[0], Length(Samples));
      if Count > 0 then Inc(Total, Count);
      if GetTickCount64 >= NextReport then
      begin
        WriteLn(Receiver.Status);
        WriteLn('totalSamples=', Total);
        Flush(Output);
        NextReport := GetTickCount64 + 1000;
      end;
      Sleep(10);
    end;
  finally
    Receiver.Free;
  end;
end.
