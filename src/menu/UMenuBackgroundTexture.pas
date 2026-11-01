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
 *
 * $URL$
 * $Id$
 *}

unit UMenuBackgroundTexture;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UThemes,
  UMenuBackground,
  UPath,
  URenderer;

//TMenuBackgroundColor - Background Color
//--------

type
  TMenuBackgroundTexture = class (TMenuBackground)
    private
      Tex: TTexture;
      Color: TRGB;
      Motion: real;
    public
      constructor Create(const ThemedSettings: TThemeBackground); override;
      procedure   Draw; override;
      destructor  Destroy; override;
  end;

const
  SUPPORTED_EXTS_BACKGROUNDTEXTURE: array[0..12] of string = ('.png', '.bmp', '.jpg', '.jpeg', '.pnm', '.ppm', '.pgm', '.pbm', '.xpm', '.lbm', '.pcx', '.tga', '.tiff');

implementation
uses
  USkins,
  Math,
  sdl2,
  SysUtils,
  UGraphic,
  UScale;

constructor TMenuBackgroundTexture.Create(const ThemedSettings: TThemeBackground);
var
  texFilename: IPath;
begin
  inherited;

  if (Length(ThemedSettings.Tex) = 0) then
    raise EMenuBackgroundError.Create('TMenuBackgroundTexture: No texture filename present');

  Color       := ThemedSettings.Color;
  Motion      := ThemedSettings.Motion;

  texFilename := Skin.GetTextureFileName(ThemedSettings.Tex);
  Tex         := Renderer.GetTexture(texFilename, TEXTURE_TYPE_PLAIN);

  if (Tex = nil) then
    raise EMenuBackgroundError.Create('TMenuBackgroundTexture: Can''t load texture');
end;

destructor  TMenuBackgroundTexture.Destroy;
begin
  Tex.Free;
  inherited;
end;

procedure   TMenuBackgroundTexture.Draw;
var
  Phase: double;
begin
  if SuppressDrawing then Exit;
  If (ScreenAct = 1) then //Clear just once when in dual screen mode
    Renderer.ClearFrameBuffer(CLEAR_DEPTH);

  with Tex do
  begin
    X := 0;
    Y := 0;
    W := RenderW;
    H := RenderH;
    if Motion > 0 then
    begin
      // Extend the canvas beyond the viewport while the image drifts.
      Phase := SDL_GetTicks / 1000 * Motion;
      W := RenderW * 1.3;
      H := RenderH * 1.3;
      X := RenderW * (-0.15 + 0.13 * Sin(Phase * 0.11));
      Y := RenderH * (-0.15 + 0.13 * Cos(Phase * 0.083));
    end;
    ColR := Color.R;
    ColG := Color.G;
    ColB := Color.B;
    ScaleMode := lsUniform;
    EdgeExtend := true;
    EdgeExtendAllowUpscale := false;
    EdgeExtendSolidFill := false;
    EdgeExtendPixels := 16;
  end;
  Renderer.DrawTexture(Tex);
end;

end.
