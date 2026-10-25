{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *}

unit UVideoPresenter;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UMusic,
  URenderer,
  UPath;

type
  // Decoder-independent video layout and drawing. The decoder owns fFrameTex;
  // it may be an uploaded frame or the texture owned by a render target.
  TVideoPresenter = class(TInterfacedObject, IVideo)
  protected
    fFrameTex: TTexture;
    fFrameTexValid: boolean;
    fTexWidth, fTexHeight: cardinal;
    fScaledWidth, fScaledHeight: cardinal;
    fScreen: integer;
    fPosX, fPosY, fPosZ: double;
    fWidth, fHeight: double;
    fFrameRange: TRectCoords;
    fAlpha: double;
    fAspect: real;
    fAspectCorrection: TAspectCorrection;

    procedure ResetPresentation;
    procedure GetVideoRect(var ScreenRect, TexRect: TRectCoords);
    procedure DrawBorders(ScreenRect: TRectCoords);

  public
    constructor Create;

    function Open(const FileName: IPath): boolean; virtual; abstract;
    procedure Close; virtual; abstract;
    procedure Play; virtual; abstract;
    procedure Pause; virtual; abstract;
    procedure Stop; virtual; abstract;
    procedure SetLoop(Enable: boolean); virtual; abstract;
    function GetLoop(): boolean; virtual; abstract;
    procedure SetPosition(Time: real); virtual; abstract;
    function GetPosition: real; virtual; abstract;
    procedure GetFrame(Time: Extended); virtual; abstract;

    procedure SetScreen(Screen: integer);
    function GetScreen(): integer;
    procedure SetScreenPosition(X, Y: double; Z: double = 0.0);
    procedure GetScreenPosition(var X, Y, Z: double);
    procedure SetWidth(Width: double);
    function GetWidth(): double;
    procedure SetHeight(Height: double);
    function GetHeight(): double;
    procedure SetFrameRange(Range: TRectCoords);
    function GetFrameRange(): TRectCoords;
    function GetFrameAspect(): real;
    procedure SetAspectCorrection(AspectCorrection: TAspectCorrection);
    function GetAspectCorrection(): TAspectCorrection;
    procedure SetAlpha(Alpha: double);
    function GetAlpha(): double;
    procedure SetReflection(Enabled: boolean);
    function GetReflection: boolean;
    procedure SetReflectionSpacing(Spacing: double);
    function GetReflectionSpacing(): double;
    procedure Draw(); virtual;
  end;

implementation

uses
  SysUtils,
  UGraphic;

constructor TVideoPresenter.Create;
begin
  inherited Create;
  ResetPresentation;
end;

procedure TVideoPresenter.ResetPresentation;
begin
  fFrameTexValid := false;
  fScreen := 1;

  fPosX := 0;
  fPosY := 0;
  fPosZ := 0;
  fWidth := RenderW;
  fHeight := RenderH;

  fFrameRange.Left := 0;
  fFrameRange.Right := 1;
  fFrameRange.Upper := 0;
  fFrameRange.Lower := 1;

  fAlpha := 1;
end;

procedure TVideoPresenter.GetVideoRect(var ScreenRect, TexRect: TRectCoords);
var
  ScreenAspect: double;  // aspect of screen resolution
  ScaledVideoWidth, ScaledVideoHeight: double;

begin
  // Three aspects to take into account:
  //  1. Screen/display resolution (e.g. 1920x1080 -> 16:9)
  //  2. Render aspect (fWidth x fHeight -> variable)
  //  3. Movie aspect (video frame aspect stored in fAspect)
  ScreenAspect := (fWidth*VertexW)/(fHeight*VertexH);

  case fAspectCorrection of
    acoCrop: begin
      if (ScreenAspect >= fAspect) then
      begin
        ScaledVideoWidth  := fWidth;
        ScaledVideoHeight := fHeight * ScreenAspect/fAspect;
      end else
      begin
        ScaledVideoHeight := fHeight;
        ScaledVideoWidth  := fWidth * fAspect/ScreenAspect;
      end;
    end;

    acoHalfway: begin
      ScaledVideoWidth  := (fWidth + fWidth * fAspect/ScreenAspect)/2;
      ScaledVideoHeight := (fHeight + fHeight * ScreenAspect/fAspect)/2;
    end;

    acoLetterBox: begin
      if (ScreenAspect <= fAspect) then
      begin
        ScaledVideoWidth  := fWidth;
        ScaledVideoHeight := fHeight * ScreenAspect/fAspect;
      end else
      begin
        ScaledVideoHeight := fHeight;
        ScaledVideoWidth  := fWidth * fAspect/ScreenAspect;
      end;
    end else
      raise Exception.Create('Unhandled aspect correction!');
  end;

  //center video
  ScreenRect.Left  := (fWidth - ScaledVideoWidth) / 2 + fPosX;
  ScreenRect.Right := ScreenRect.Left + ScaledVideoWidth;
  ScreenRect.Upper := (fHeight - ScaledVideoHeight) / 2 + fPosY;
  ScreenRect.Lower := ScreenRect.Upper + ScaledVideoHeight;

  // texture contains right/lower (power-of-2) padding.
  // Determine the texture coords of the video frame.
  TexRect.Left  := (fScaledWidth / fTexWidth) * fFrameRange.Left;
  TexRect.Right := (fScaledWidth / fTexWidth) * fFrameRange.Right;
  TexRect.Upper := (fScaledHeight / fTexHeight) * fFrameRange.Upper;
  TexRect.Lower := (fScaledHeight / fTexHeight) * fFrameRange.Lower;
end;

procedure TVideoPresenter.DrawBorders(ScreenRect: TRectCoords);
var
  QuadList: TQuadList;

  procedure DrawRect(left, right, upper, lower: single);
  begin
    SetLength(QuadList, Length(QuadList) + 1);
    with QuadList[High(QuadList)] do
    begin
      X := left;
      Y := upper;
      Z := fPosZ;
      W := right - left;
      H := lower - upper;
      Gradient := gdNone;
      ColR := 0;
      ColG := 0;
      ColB := 0;
      Alpha := fAlpha;
    end;
  end;
begin
  //upper border
  if(ScreenRect.Upper > fPosY) then
    DrawRect(fPosX, fPosX+fWidth, fPosY, ScreenRect.Upper);

  //lower border
  if(ScreenRect.Lower < fPosY+fHeight) then
    DrawRect(fPosX, fPosX+fWidth, ScreenRect.Lower, fPosY+fHeight);

  //left border
  if(ScreenRect.Left > fPosX) then
    DrawRect(fPosX, ScreenRect.Left, fPosY, fPosY+fHeight);

  //right border
  if(ScreenRect.Right < fPosX+fWidth) then
    DrawRect(ScreenRect.Right, fPosX+fWidth, fPosY, fPosY+fHeight);

  if (Length(QuadList) > 0 ) then
    Renderer.DrawQuads(QuadList);
end;

procedure TVideoPresenter.Draw();
var
  ScreenRect:   TRectCoords;
  TexRect:      TRectCoords;
begin
  // exit if there's nothing to draw
  if (not assigned(fFrameTex)) then
    Exit;

  // get texture and screen positions
  GetVideoRect(ScreenRect, TexRect);

  Renderer.SetScissorRect(
    round(fPosX*VertexW + (ScreenWPerScreen)*(fScreen-1)),
    round((RenderH-fPosY-fHeight)*VertexH),
    round(fWidth*VertexW),
    round(fHeight*VertexH)
    );

  Renderer.ScissorTest := true;
  with fFrameTex do
  begin
    X := ScreenRect.Left;
    Y := ScreenRect.Upper;
    Z := fPosZ;
    W := ScreenRect.Right - ScreenRect.Left;
    H := ScreenRect.Lower - ScreenRect.Upper;
    Alpha := fAlpha;
    TexX1 := TexRect.Left;
    TexY1 := TexRect.Upper;
    TexX2 := TexRect.Right;
    TexY2 := TexRect.Lower;
  end;
  Renderer.DrawTexture(fFrameTex);

  //draw black borders
  DrawBorders(ScreenRect);
  Renderer.ScissorTest := false;

end;

procedure TVideoPresenter.SetScreen(Screen: integer);
begin
  fScreen := Screen;
end;

function TVideoPresenter.GetScreen(): integer;
begin
  Result := fScreen;
end;


procedure TVideoPresenter.SetScreenPosition(X, Y, Z: double);
begin
  fPosX := X;
  fPosY := Y;
  fPosZ := Z;
end;

procedure TVideoPresenter.GetScreenPosition(var X, Y, Z: double);
begin
  X := fPosX;
  Y := fPosY;
  Z := fPosZ;
end;


procedure TVideoPresenter.SetWidth(Width: double);
begin
  fWidth := Width;
end;

function TVideoPresenter.GetWidth(): double;
begin
  Result := fWidth;
end;


procedure TVideoPresenter.SetHeight(Height: double);
begin
  fHeight := Height;
end;

function TVideoPresenter.GetHeight(): double;
begin
  Result := fHeight;
end;


procedure TVideoPresenter.SetFrameRange(Range: TRectCoords);
begin
  fFrameRange := Range;
end;

function TVideoPresenter.GetFrameRange(): TRectCoords;
begin
  Result := fFrameRange;
end;


function TVideoPresenter.GetFrameAspect(): real;
begin
  Result := fAspect;
end;


procedure TVideoPresenter.SetAspectCorrection(AspectCorrection: TAspectCorrection);
begin
  fAspectCorrection := AspectCorrection;
end;

function TVideoPresenter.GetAspectCorrection(): TAspectCorrection;
begin
  Result := fAspectCorrection;
end;

procedure TVideoPresenter.SetAlpha(Alpha: double);
begin
  fAlpha := Alpha;

  if (fAlpha>1) then
    fAlpha := 1;

  if (fAlpha<0) then
    fAlpha := 0;
end;

function TVideoPresenter.GetAlpha(): double;
begin
  Result := fAlpha;
end;

procedure TVideoPresenter.SetReflection(Enabled: boolean);
begin
  if (assigned(fFrameTex)) then
    fFrameTex.Reflection := Enabled
end;

function TVideoPresenter.GetReflection: boolean;
begin
  if (assigned(fFrameTex)) then
    Result := fFrameTex.Reflection
  else
    Result := false;
end;

procedure TVideoPresenter.SetReflectionSpacing(Spacing: double);
begin
  if (assigned(fFrameTex)) then
    fFrameTex.ReflectionSpacing:= Spacing;
end;

function TVideoPresenter.GetReflectionSpacing(): double;
begin
  if (assigned(fFrameTex)) then
    Result := fFrameTex.ReflectionSpacing
  else
    Result := 0;
end;


end.
