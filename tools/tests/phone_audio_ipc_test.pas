program phone_audio_ipc_test;
{$mode Delphi}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, URemoteBridgeIPC;
var Started, Elapsed: QWord;
    MessageText: string;
begin
  RemoteBridgeIPC.Host := '127.0.0.1';
  RemoteBridgeIPC.Port := StrToInt(ParamStr(1));
  RemoteBridgeIPC.Start;
  try
    Sleep(250);
    MessageText := '{"type":"test.backpressure","pad":"' + StringOfChar('x', 8 * 1024 * 1024) + '"}';
    Started := GetTickCount64;
    RemoteBridgeIPC.SendJsonMessage(MessageText);
    Elapsed := GetTickCount64 - Started;
    WriteLn('Main-thread send elapsed ms=', Elapsed);
    if Elapsed > 250 then Halt(1);
    Sleep(100);
  finally
    RemoteBridgeIPC.Stop;
  end;
end.
