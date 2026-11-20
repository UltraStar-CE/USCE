program input_roster_test;
{$mode Delphi}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}SysUtils, UIni, URecord, URemoteInput, UPhoneAudio;
type TTestDevice = class(TAudioInputDevice)
  function Stop: boolean; override;
end;
function TTestDevice.Stop: boolean;
begin Result := true; end;
procedure ExpectCount(Expected: integer; LocalCount: integer = IMaxPlayerCount;
  ExpectedSlots: cardinal = High(cardinal));
var Actual: integer; Slots: cardinal;
begin
  Actual := AudioInputProcessor.ConfiguredPlayerCount(LocalCount, Slots);
  if Actual <> Expected then
    raise Exception.CreateFmt('Expected %d players, got %d', [Expected, Actual]);
  if (ExpectedSlots <> High(cardinal)) and (Slots <> ExpectedSlots) then
    raise Exception.CreateFmt('Expected slot mask %d, got %d', [ExpectedSlots, Slots]);
end;
var Device: TAudioInputDevice;
begin
  Ini := TIni.Create;
  RemoteInputProcessor.Clear;
  ExpectCount(0);
  Ini.SlotDelay[0] := 24;
  Ini.SlotDelay[1] := -18;
  RemoteInputProcessor.AssignPlayerSlot(0, 'one', 'controller', 1, 31);
  if RemoteInputProcessor.AssignedMicDelayMs(0) <> 31 then
    raise Exception.Create('Assigned phone delay is unavailable');
  ExpectCount(1);
  RemoteInputProcessor.ClearPlayerSlot(0);
  RemoteInputProcessor.AssignPlayerSlot(1, 'one', 'controller', 2, 31);
  RemoteInputProcessor.SetPlayerDelayMs(1, -7);
  if (RemoteInputProcessor.AssignedMicDelayMs(0) <> 0) or
    (RemoteInputProcessor.AssignedMicDelayMs(1) <> -7) or
    (Ini.SlotDelay[0] <> 24) or (Ini.SlotDelay[1] <> -18) then
    raise Exception.Create('Moving or adjusting a phone changed a slot delay');
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
  ExpectCount(2, 1); // The configured local slot 7 is beyond the selection.
  RemoteInputProcessor.Clear;
  ExpectCount(7);
  ExpectCount(0, 1);
  Ini.InputDeviceConfig[0].ChannelToPlayerMap[0] := IMaxPlayerCount;
  ExpectCount(IMaxPlayerCount);
  SetLength(Ini.InputDeviceConfig[0].ChannelToPlayerMap, 2);
  Ini.InputDeviceConfig[0].ChannelToPlayerMap[0] := 1;
  Ini.InputDeviceConfig[0].ChannelToPlayerMap[1] := 2;
  RemoteInputProcessor.AssignPlayerSlot(2, 'three', 'controller', 3, 0);
  ExpectCount(3, 1, 5); // The second local mic must not fill slot 2.
  ExpectCount(3, 0, 4);
  RemoteInputProcessor.Clear;
  ExpectCount(1, 1, 1);
  SetLength(Ini.InputDeviceConfig[0].ChannelToPlayerMap, 1);
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
  WriteLn('PASS: zero inputs, remote slots, sparse local slots, local limits, disconnects and full-array polling');
end.
