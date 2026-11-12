program phone_audio_profile_test;
{$mode Delphi}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, UIni, URemoteBridgeIPC;
var Deadline: QWord;
begin
  Ini := TIni.Create;
  SetLength(IPlayersVals, 2);
  IPlayersVals[0] := 1;
  IPlayersVals[1] := 2;
  RemoteBridgeIPC.Host := '127.0.0.1';
  RemoteBridgeIPC.Port := StrToInt(ParamStr(1));
  RemoteBridgeIPC.Start;
  try
    Deadline := GetTickCount64 + 5000;
    repeat
      Sleep(20);
      RemoteBridgeIPC.ApplyPendingPlayerCount;
    until (Ini.Name[1] = 'Phone on Mic 2') or (GetTickCount64 >= Deadline);
    if Ini.Name[1] <> 'Phone on Mic 2' then
      raise Exception.Create('Controller assigned Mic 2 did not receive its game profile');
    if IPlayersVals[Ini.Players] <> 2 then
      raise Exception.Create('Mic 2 did not expand the game player count');
    if Ini.PlayerLevel[1] <> 2 then
      raise Exception.Create('Mic 2 difficulty was not applied');
    WriteLn('PASS: a controller on Mic 2 receives its name, difficulty and player count');
  finally
    RemoteBridgeIPC.Stop;
    Ini.Free;
    Ini := nil;
  end;
end.
