unit UInputSource;
{$mode Delphi}{$H+}
interface
uses UScale;
type TPlayerInputSource = (pisNone, pisLocal, pisDirect, pisServer);
  TInputBadgeScreen = (ibsSetup, ibsSing, ibsScore);
function PlayerInputSource(PlayerIndex: integer): TPlayerInputSource;
procedure DrawInputSourceBadge(Source: TPlayerInputSource; X, Y, W, H: single;
  Screen: TInputBadgeScreen = ibsSetup; Opacity: single = 1;
  LayoutMode: TLayoutScaleMode = lsStretch);
procedure ReleaseInputSourceBadges;
implementation
uses Math, SysUtils, Types, UIni, URecord, URemoteInput, UPhoneAudio, URenderer,
  UThemes, USkins, fpjson, jsonparser;
var CachedAt: array[0..IMaxPlayerCount-1] of QWord;
    CachedSource: array[0..IMaxPlayerCount-1] of TPlayerInputSource;
    Glyphs: array[pisLocal..pisServer] of TTexture;
function PlayerInputSource(PlayerIndex: integer): TPlayerInputSource;
var Local: TBooleanDynArray; Data: TJSONData;
begin
  Result := pisNone;
  if (PlayerIndex < 0) or (PlayerIndex >= IMaxPlayerCount) then Exit;
  if RemoteInputProcessor.HasAssignedPlayer(PlayerIndex) then
  begin
    if (CachedAt[PlayerIndex] = 0) or (GetTickCount64 - CachedAt[PlayerIndex] >= 100) then
    begin
      CachedAt[PlayerIndex] := GetTickCount64;
      CachedSource[PlayerIndex] := pisServer;
      Data := nil;
      try
        try
          if PhoneAudio.Enabled then
          begin
            Data := GetJSON(string(PhoneAudio.Status(PlayerIndex)));
            if (Data is TJSONObject) and (TJSONObject(Data).Get('audioRoute', '') = 'direct') then
              CachedSource[PlayerIndex] := pisDirect;
          end;
        except end;
      finally Data.Free; end;
    end;
    Exit(CachedSource[PlayerIndex]);
  end;
  CachedAt[PlayerIndex] := 0;
  AudioInputProcessor.CheckPlayersConfig(IMaxPlayerCount, Local);
  if Local[PlayerIndex] then Result := pisLocal;
end;
function SegmentDistance(X,Y,X1,Y1,X2,Y2: double): double;
var T, DX, DY: double;
begin
  DX:=X2-X1; DY:=Y2-Y1;
  T:=EnsureRange(((X-X1)*DX+(Y-Y1)*DY)/Max(0.0001,DX*DX+DY*DY),0.0,1.0);
  Result:=Hypot(X-X1-T*DX,Y-Y1-T*DY);
end;

function ArcDistance(X,Y,CX,CY,Radius,A,B: double): double;
var Angle: double;
begin
  Angle:=ArcTan2(Y-CY,X-CX);
  if Angle<0 then Angle:=Angle+2*Pi;
  if (Angle>=A) and (Angle<=B) then Result:=Abs(Hypot(X-CX,Y-CY)-Radius)
  else Result:=Min(Hypot(X-CX-Cos(A)*Radius,Y-CY-Sin(A)*Radius),
    Hypot(X-CX-Cos(B)*Radius,Y-CY-Sin(B)*Radius));
end;

function CreateBadgeGlyph(Source: TPlayerInputSource): TTexture;
const Resolution=96;
var Pixels: array[0..Resolution*Resolution*4-1] of byte;
  PX,PY,I,Offset: integer; X,Y,D,Coverage: double;
begin
  // Rasterize once with subpixel coverage, then use the renderer's filtered
  // texture path. No platform-specific line rasterization or extra assets.
  for PY:=0 to Resolution-1 do
    for PX:=0 to Resolution-1 do
    begin
      X:=(PX+0.5)*24/Resolution; Y:=(PY+0.5)*24/Resolution;
      if Source=pisLocal then
      begin
        D:=SegmentDistance(X,Y,10,6,10,11)-2.5;
        D:=Min(D,ArcDistance(X,Y,10,11,5,0,Pi)-0.8);
        D:=Min(D,SegmentDistance(X,Y,5,9,5,11)-0.8);
        D:=Min(D,SegmentDistance(X,Y,15,9,15,11)-0.8);
        D:=Min(D,SegmentDistance(X,Y,10,16,10,20)-0.8);
        D:=Min(D,SegmentDistance(X,Y,10,20,18,20)-0.8);
        D:=Min(D,SegmentDistance(X,Y,18,20,18,17)-0.8);
      end
      else
      begin
        D:=Hypot(X-12,Y-20)-1.2;
        for I:=1 to 3 do D:=Min(D,ArcDistance(X,Y,12,20,I*5,Pi*1.25,Pi*1.75)-0.85);
        if Source=pisServer then
        begin
          // Clear a small area behind the exclamation mark for legibility.
          if (X>18) and (Y>10) then D:=100;
          D:=Min(D,SegmentDistance(X,Y,21,11,21,16)-0.9);
          D:=Min(D,Hypot(X-21,Y-19)-1);
        end;
      end;
      Coverage:=EnsureRange(0.5-D*Resolution/24,0.0,1.0);
      Offset:=(PY*Resolution+PX)*4;
      Pixels[Offset]:=255; Pixels[Offset+1]:=255; Pixels[Offset+2]:=255;
      Pixels[Offset+3]:=Round(Coverage*255);
    end;
  Result:=Renderer.CreateTexture(PChar(@Pixels[0]),nil,Resolution,Resolution,TEXTURE_TYPE_TRANSPARENT);
end;

procedure ReleaseInputSourceBadges;
var Source: TPlayerInputSource;
begin
  for Source:=pisLocal to pisServer do FreeAndNil(Glyphs[Source]);
end;

procedure DrawInputSourceBadge(Source: TPlayerInputSource; X, Y, W, H: single;
  Screen: TInputBadgeScreen; Opacity: single; LayoutMode: TLayoutScaleMode);
var Size,Inset: single; Style: TInputSourceBadgeTheme; Texture: TTexture; Custom: string;
begin
  if (Source=pisNone) or (W<=0) or (H<=0) then Exit;
  ResolveLayoutRect(X,Y,W,H,LayoutMode);
  Style:=Theme.InputSourceBadges[Ord(Screen)];
  if not Style.Visible or (Style.Alpha<=0) or (Opacity<=0) then Exit;
  Inset:=Min(Style.Inset,Min(W,H)*0.1);
  Size:=Min(Style.Size,Min(W,H)-2*Inset);
  if Size<=0 then Exit;
  if Style.Corner in [1,3] then X:=X+W-Size-Inset else X:=X+Inset;
  if Style.Corner in [2,3] then Y:=Y+H-Size-Inset else Y:=Y+Inset;
  case Source of
    pisLocal: Custom:=Style.LocalTexture;
    pisDirect: Custom:=Style.DirectTexture;
    pisServer: Custom:=Style.ServerTexture;
  end;
  if Custom<>'' then Texture:=Renderer.GetTexture(Skin.GetTextureFileName(Custom),TEXTURE_TYPE_TRANSPARENT)
  else
  begin
    if Glyphs[Source]=nil then Glyphs[Source]:=CreateBadgeGlyph(Source);
    Texture:=Glyphs[Source];
  end;
  Texture.X:=X; Texture.Y:=Y; Texture.Z:=1; Texture.W:=Size; Texture.H:=Size;
  Texture.ScaleMode:=lsUniform;
  Texture.Alpha:=Style.Alpha*EnsureRange(Opacity,0.0,1.0);
  if Source=pisServer then
  begin
    Texture.ColR:=Style.ServerColor.R; Texture.ColG:=Style.ServerColor.G; Texture.ColB:=Style.ServerColor.B;
  end
  else
  begin
    Texture.ColR:=Style.Color.R; Texture.ColG:=Style.Color.G; Texture.ColB:=Style.Color.B;
  end;
  Renderer.DrawTexture(Texture);
end;
end.
