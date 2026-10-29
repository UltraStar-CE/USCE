program relay_socket_test;
{$MODE Delphi}{$H+}{$CODEPAGE UTF8}{$ASSERTIONS ON}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, URemoteRelaySocket;
var Socket: TRemoteRelaySocket;
    Deadline: QWord;
    Expected, Actual: UTF8String;
    I: integer;
begin
  Assert(ParamCount = 2, 'Usage: relay_socket_test library-path echo-websocket-url');
  Socket := TRemoteRelaySocket.Create;
  try
    Assert(Socket.State = 3);
    Assert(not Socket.Send('{}'));
    Assert(not Socket.Open('https://example.invalid/', ParamStr(1)));
    Assert(Socket.LastError <> '');
    for I := 1 to 2 do
    begin
      Assert(Socket.Open(UTF8String(ParamStr(2)), ParamStr(1)), Socket.LastError);
      Deadline := GetTickCount64 + 5000;
      while Socket.State = 0 do
      begin
        Assert(GetTickCount64 < Deadline, 'Connect timed out');
        Sleep(5);
      end;
      Assert(Socket.State = 1, 'WebSocket failed to open');
      Expected := '{"text":"Grüße 🎤","type":"test"}';
      if I = 2 then Expected := UTF8String(StringOfChar('x', 1024 * 1024));
      Assert(not Socket.Send(''));
      Assert(not Socket.Send('bad' + #0 + 'text'));
      Assert(Socket.Send(Expected));
      Deadline := GetTickCount64 + 5000;
      while not Socket.Receive(Actual) do
      begin
        Assert(GetTickCount64 < Deadline, 'Echo timed out');
        Sleep(5);
      end;
      Assert(Actual = Expected, 'UTF-8 or large payload changed across ABI');
      Assert(not Socket.Receive(Actual));
      Socket.Close;
      Socket.Close;
      Assert(Socket.State = 3);
    end;
  finally
    Socket.Free;
  end;
  WriteLn('Pascal relay ABI: real echo, UTF-8, 1 MiB message, close/reopen passed');
end.
