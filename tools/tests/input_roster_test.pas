program input_roster_test;
{$mode Delphi}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}SysUtils, UIni, URecord, URemoteInput, UPhoneAudio;
type TTestDevice = class(TAudioInputDevice)
  function Stop: boolean; override;
end;
function TTestDevice.Stop: boolean;
begin Result := true; end;
procedure ExpectCount(Expected: integer);
begin
  if AudioInputProcessor.ConfiguredPlayerCount <> Expected then
    raise Exception.CreateFmt('Expected %d players, got %d', [Expected, AudioInputProcessor.ConfiguredPlayerCount]);
end;
var Device: TAudioInputDevice;
begin
  Ini := TIni.Create;
  RemoteInputProcessor.Clear;
  ExpectCount(0);
  RemoteInputProcessor.AssignPlayerSlot(0, 'one', 'controller', 1, 0);
  ExpectCount(1);
  RemoteInputProcessor.ClearPlayerSlot(0);
  RemoteInputProcessor.AssignPlayerSlot(1, 'one', 'controller', 2, 0);
  ExpectCount(2);
  RemoteInputProcessor.ClearFrames;
  ExpectCount(2); // A transport loss cannot erase singers or live scores.
  if RemoteInputProcessor.AssignedPlayerId(1) <> 'one' then
    raise Exception.Create('Temporary transport loss changed the singer identity');
  SetLength(Ini.InputDeviceConfig, 1);
  SetLength(Ini.InputDeviceConfig[0].ChannelToPlayerMap, 1);
  Ini.InputDeviceConfig[0].ChannelToPlayerMap[0] := 7;
  Device := TTestDevice.Create;
  Device.CfgIndex := 0;
  SetLength(AudioInputProcessor.DeviceList, 1);
  AudioInputProcessor.DeviceList[0] := Device;
  ExpectCount(7);
  RemoteInputProcessor.Clear;
  ExpectCount(7);
  Ini.InputDeviceConfig[0].ChannelToPlayerMap[0] := IMaxPlayerCount;
  ExpectCount(IMaxPlayerCount);
  Ini.InputDeviceConfig[0].ChannelToPlayerMap[0] := 0;
  ExpectCount(0);
  if ParamStr(1) <> '' then
  begin
    if not PhoneAudio.Start('ipc://', '', ParamStr(1)) then raise Exception.Create(PhoneAudio.LastError);
    UpdatePhoneAudio; // Polling the full local-player array must also work above remote slot 12.
    ExpectCount(0); // Enabling the receiver must never invent a local microphone.
    PhoneAudio.Stop;
  end;
  SetLength(AudioInputProcessor.DeviceList, 0);
  Device.Free;
  Ini.Free;
  Ini := nil;
  WriteLn('PASS: zero inputs, remote 1/2, sparse local 7/24, disconnects and full-array polling');
end.
