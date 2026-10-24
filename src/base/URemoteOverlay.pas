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
  UText, UThemes, UGraphic,
  URemoteBridgeIPC;

procedure DrawRemoteRoomOverlay;
var
  Connected: boolean;
  DisplayCode: UTF8String;
  StatusSeq: integer;
  ConnectedPlayers: integer;
  Text: UTF8String;
  TextW, X: real;
begin
  if not Theme.RemoteRoomVisible then Exit;
  RemoteBridgeIPC.GetRoomStatus(Connected, DisplayCode, StatusSeq, ConnectedPlayers);
  if (not Connected) then
    Exit;

  if (DisplayCode = '') then
    Text := 'usdx.at connecting'
  else
    Text := 'usdx.at/' + DisplayCode + '  ' + IntToStr(ConnectedPlayers) + ' player';
  if (ConnectedPlayers <> 1) and (DisplayCode <> '') then
    Text := Text + 's';

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
