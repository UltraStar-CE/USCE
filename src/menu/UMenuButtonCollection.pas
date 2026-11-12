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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/menu/UMenuButtonCollection.pas $
 * $Id: UMenuButtonCollection.pas 1692 2009-04-24 18:43:12Z k-m_schindler $
 *}

unit UMenuButtonCollection;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UMenuButton, Math;

type
  //----------------
  //TButtonCollection
  //No Extra Attributes or Functions ATM
  //----------------
  AButton = array of TButton;
  PAButton = ^AButton;
  TButtonCollection = class(TButton)
    //num of the First Button, that can be Selected
    FirstChild: byte;
    CountChilds: byte;
    
    ScreenButton: PAButton;

    procedure SetSelect(Value : boolean); override;
    procedure Draw; override;
  end;

implementation

procedure TButtonCollection.SetSelect(Value : boolean);
var
  Index: integer;
begin
  inherited;

  //Set Visible for Every Button that is a Child of this ButtonCollection
  if (not Fade) then
    for Index := 0 to High(ScreenButton^) do
      if (ScreenButton^[Index].Parent = Parent) then
        ScreenButton^[Index].Visible := Value;
end;

procedure TButtonCollection.Draw;
var
  I, J: integer;
  Alpha: single;
begin
  inherited;
  //If fading is activated, Fade Child Buttons
  if (Fade) then
  begin
    for I := 0 to High(ScreenButton^) do
      if (ScreenButton^[I].Parent = Parent) then
      begin
        if (FadeProgress < 0.5) then
        begin
          ScreenButton^[I].Visible := SelectBool;

          for J := 0 to High(ScreenButton^[I].Text) do
            ScreenButton^[I].Text[J].Visible := SelectBool;
        end
        else
        begin
          Alpha := EnsureRange((FadeProgress-0.666)*3, 0.0, 1.0);
          ScreenButton^[I].Texture.Alpha := Alpha * ScreenButton^[I].BackgroundAlpha;
          ScreenButton^[I].DeSelectTexture.Alpha := Alpha * ScreenButton^[I].BackgroundAlpha;
          
          for J := 0 to High(ScreenButton^[I].Text) do
            ScreenButton^[I].Text[J].Alpha := Alpha;
        end;
      end;
  end;
end;

end.
