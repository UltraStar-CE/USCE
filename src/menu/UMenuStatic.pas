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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/menu/UMenuStatic.pas $
 * $Id: UMenuStatic.pas 1692 2009-04-24 18:43:12Z k-m_schindler $
 *}

unit UMenuStatic;

interface

{$IFDEF FPC}
  {$MODE Delphi}
  {$CODEPAGE UTF8}
{$ENDIF}

{$I switches.inc}

uses
  URenderer,
  UMenuInteract;

type
  TStatic = class
    public
      Texture:           TTexture; // Button Screen position and size
      Visible:           boolean;
      KeyCap:            UTF8String;

      // for list item
      TextureSelect:     TTexture;
      TextureDeselect:   TTexture; // Button Screen position and size

      //Reflection Mod
      Reflection:        boolean;
      Reflectionspacing: single;

      procedure Draw;
      constructor Create(Textura: TTexture); overload;
      destructor Destroy; override;
      function GetMouseOverArea: TMouseOverRect;
  end;

implementation
uses
  Math, UDisplay, UFont, UMenuText, UScale, UText;

procedure DrawNavigationArrows(X, Y, Z, W, H, Alpha: real;
  Reflection: boolean; ReflectionSpacing: real);
var
  Size, CenterX, CenterY, MirrorY, ReflectionAlpha: real;

  procedure Arrow(ArrowX, ArrowY, DirX, DirY, Opacity: real);
  begin
    Renderer.DrawTriangle(
      ArrowX + DirX * Size, ArrowY + DirY * Size,
      ArrowX + (DirY - DirX) * Size, ArrowY - (DirX + DirY) * Size,
      ArrowX - (DirY + DirX) * Size, ArrowY + (DirX - DirY) * Size,
      Z, 0.08, 0.12, 0.18, Opacity);
  end;

begin
  Size := Min(W / 9, H / 5);
  CenterX := X + W / 2;
  CenterY := Y + H / 2;
  Arrow(CenterX, CenterY - Size, 0, -1, Alpha);
  Arrow(CenterX - 2.4 * Size, CenterY + Size, -1, 0, Alpha);
  Arrow(CenterX, CenterY + Size, 0, 1, Alpha);
  Arrow(CenterX + 2.4 * Size, CenterY + Size, 1, 0, Alpha);
  if Reflection then
  begin
    // Only the lower row falls inside the keycap's half-height reflection.
    MirrorY := Y + H + ReflectionSpacing + H / 2 - Size;
    ReflectionAlpha := Max(0, Alpha - REFLECTION_ALPHA_DIFF) * Size / (H / 2);
    Arrow(CenterX - 2.4 * Size, MirrorY, -1, 0, ReflectionAlpha);
    Arrow(CenterX, MirrorY, 0, -1, ReflectionAlpha);
    Arrow(CenterX + 2.4 * Size, MirrorY, 1, 0, ReflectionAlpha);
  end;
end;

procedure TStatic.Draw;
var
  X, Y, W, H, Size, LabelX, LabelY, Ascender, CapReflectionSpacing: real;
  Bounds: TBoundsDbl;
begin
  if not Visible then Exit;
  if KeyCap <> '' then
  begin
    X := Texture.X; Y := Texture.Y; W := Texture.W; H := Texture.H;
    ResolveLayoutRect(X, Y, W, H, Texture.ScaleMode);
    // Keep the cap inside the old icon's slot and leave space for its label.
    X := X + 2; Y := Y + 4; W := W - 4; H := H - 8;
    if (W <= 0) or (H <= 0) then Exit;
    // Mirror the inset keycap at the original icon's reflection line.
    CapReflectionSpacing := ReflectionSpacing + 8;
    DrawKeyFrame(X, Y, Texture.Z, W, H, 0.08, 0.12, 0.18, Texture.Alpha,
      Reflection, CapReflectionSpacing);
    if KeyCap = '←↑↓→' then
    begin
      DrawNavigationArrows(X, Y, Texture.Z, W, H, Texture.Alpha,
        Reflection, CapReflectionSpacing);
      Exit;
    end;
    SetFont(0, ftBold);
    SetFontItalic(false);
    Size := H * 0.67;
    SetFontSize(Size);
    while (Size > 1) and (TextWidth(KeyCap) > W - 4) do
    begin
      Size := Size - 1;
      SetFontSize(Size);
    end;
    Bounds := Fonts[CurrentFont.FontFamily][CurrentFont.FontStyle].Font.BBox(KeyCap, false);
    Ascender := Fonts[CurrentFont.FontFamily][CurrentFont.FontStyle].Font.Ascender;
    LabelX := X + (W - TextWidth(KeyCap)) / 2;
    LabelY := Y + H / 2 - Ascender + (Bounds.Top + Bounds.Bottom) / 2;
    SetFontReflection(Reflection, CapReflectionSpacing + 2 * (Y + H - LabelY - Ascender));
    SetFontColor(0.08, 0.12, 0.18, Texture.Alpha);
    SetFontZ(Texture.Z);
    SetFontPos(LabelX, LabelY);
    PrintText(KeyCap);
    ResetFont;
  end
  else
  begin
    Texture.Reflection := Reflection;
    Texture.ReflectionSpacing := ReflectionSpacing;
    Renderer.DrawTexture(Texture);
  end;
end;

constructor TStatic.Create(Textura: TTexture);
begin
  inherited Create;
  Texture := Textura;
end;

destructor TStatic.Destroy();
begin
  Texture.Free;
  TextureSelect.Free;
  TextureDeselect.Free;
  inherited;
end;

function TStatic.GetMouseOverArea: TMouseOverRect;
begin
  if not(Display.Cursor_HiddenByScreen) then
  begin
    Result.X := Texture.X;
    Result.Y := Texture.Y;
    Result.W := Texture.W;
    Result.H := Texture.H;
    ResolveLayoutRect(Result.X, Result.Y, Result.W, Result.H, Texture.ScaleMode);
  end;
end;

end.
