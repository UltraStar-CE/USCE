{* UltraStar Deluxe - Karaoke Game
 *
 * Lightweight global display overlay for USDX Remote room status.
 *}

unit URemoteOverlay;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

procedure DrawRemoteRoomOverlay;

implementation

uses
  SysUtils,
  UText, UThemes, UGraphic, URenderer, ULanguage,
  UPhoneAudio, fpjson, jsonparser,
  URemoteBridgeIPC;

procedure DrawPhoneRouteWarning;
var
  Status: TJSONData;
  Route: string;
  Caption: UTF8String;
  X: real;
begin
  if not PhoneAudio.Enabled then Exit;
  Status := nil;
  Route := 'inactive';
  try
    Status := GetJSON(PhoneAudio.Status);
    if Status is TJSONObject then
      Route := TJSONObject(Status).Get('audioRoute', 'inactive');
  except
    // Missing diagnostics must not hide an unconfirmed route.
  end;
  Status.Free;
  if Route = 'direct' then Exit;
  if Route = 'server' then Caption := Language.Translate('PHONE_AUDIO_VIA_SERVER')
  else Caption := Language.Translate('PHONE_AUDIO_NO_DIRECT');
  SetFont(0, 0);
  SetFontSize(16);
  SetFontItalic(false);
  SetFontReflection(false, 0);
  SetFontZ(0);
  X := RenderW - TextWidth(Caption) - 12;
  Renderer.DrawTriangle(X - 22, 28, X - 4, 28, X - 13, 11, 0, 1, 0.78, 0.2, 1);
  Renderer.DrawLine(X - 13, 17, X - 13, 22, 0, 2, 0.15, 0.12, 0.05, 1);
  Renderer.DrawLine(X - 13, 24, X - 13, 26, 0, 2, 0.15, 0.12, 0.05, 1);
  SetFontColor(1, 0.78, 0.2, 1);
  SetFontPos(X, 10);
  PrintText(Caption);
  SetFontColor(1, 1, 1, 1);
end;

procedure DrawRemoteRoomOverlay;
var
  Connected: boolean;
  DisplayCode: UTF8String;
  StatusSeq: integer;
  ConnectedPlayers: integer;
  Text: UTF8String;
  TextW, X: real;
  Status: TJSONData;
begin
  DrawPhoneRouteWarning;
  if not Theme.RemoteRoomVisible then Exit;
  RemoteBridgeIPC.GetRoomStatus(Connected, DisplayCode, StatusSeq, ConnectedPlayers);
  if PhoneAudio.Enabled then
  begin
    Text := 'PCM status unavailable';
    Status := nil;
    try
      Status := GetJSON(PhoneAudio.Status);
      if Status is TJSONObject then
        Text := 'PCM ' + TJSONObject(Status).Get('code', '') + '  ' +
          TJSONObject(Status).Get('state', '') + '  queue ' +
          FloatToStr(TJSONObject(Status).Get('queueMs', 0.0)) + ' ms';
    except
      // An unavailable diagnostic must not interrupt rendering or singing.
    end;
    Status.Free;
  end
  else if (not Connected) then
    Exit;

  if not PhoneAudio.Enabled then
  begin
    if (DisplayCode = '') then
      Text := 'usdx.at connecting'
    else
      Text := 'usdx.at/' + DisplayCode + '  ' + IntToStr(ConnectedPlayers) + ' player';
    if (ConnectedPlayers <> 1) and (DisplayCode <> '') then
      Text := Text + 's';
  end;

  SetFont(Theme.RemoteRoomText.Font, Theme.RemoteRoomText.Style);
  SetFontSize(Theme.RemoteRoomText.Size);
  SetFontItalic(false);
  SetFontReflection(Theme.RemoteRoomText.Reflection, Theme.RemoteRoomText.ReflectionSpacing);
  SetFontZ(Theme.RemoteRoomText.Z);
  SetFontColor(Theme.RemoteRoomText.ColR, Theme.RemoteRoomText.ColG,
    Theme.RemoteRoomText.ColB, Theme.RemoteRoomAlpha);
  TextW := TextWidth(Text);
  X := Theme.RemoteRoomText.X;
  if Theme.RemoteRoomAnchorRight then X := X + RenderW;
  case Theme.RemoteRoomText.Align of
    1: X := X - TextW / 2;
    2: X := X - TextW;
  end;
  SetFontPos(X, Theme.RemoteRoomText.Y);
  PrintText(Text);
  SetFontReflection(false, 0);
  SetFontColor(1, 1, 1, 1);
end;

end.
