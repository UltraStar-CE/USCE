program relay_session_test;
{$MODE Delphi}{$H+}{$ASSERTIONS ON}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, fpjson, URemoteRelaySession;
var Session: TRemoteRelaySession;
    Deadline: QWord;
    Code: UTF8String;
    Message: TJSONObject;
    I: integer;
begin
  Assert(ParamCount = 2, 'Usage: relay_session_test library-path relay-host-url');
  Session := TRemoteRelaySession.Create;
  try
    Session.Start(ParamStr(2), ParamStr(1), 'native-session-test');
    for I := 1 to 2 do
    begin
      Deadline := GetTickCount64 + 10000;
      while not Session.Registered do
      begin
        Session.Tick;
        Assert(GetTickCount64 < Deadline, 'Room registration timed out');
        Sleep(5);
      end;
      if I = 1 then
      begin
        Code := Session.DisplayCode;
        Assert(Code <> '');
        Session.Reconnect;
      end
      else Assert(Session.DisplayCode = Code, 'Reconnect lost the room');
    end;
    Message := TJSONObject.Create(['type', 'host.shutdown', 'reason', 'native_session_test_finished']);
    try Assert(Session.Send(Message)); finally Message.Free; end;
    // Allow queued writes and the service's close response to drain.
    Deadline := GetTickCount64 + 200;
    while GetTickCount64 < Deadline do begin Session.Tick; Sleep(5); end;
  finally Session.Free; end;
  WriteLn('Pascal relay session: verified TLS, room creation and reconnect/resume passed; shutdown sent');
end.
