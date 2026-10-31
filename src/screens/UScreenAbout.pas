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
 * $URL: $
 * $Id: $
 *}

unit UScreenAbout;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UDocumentUI,
  UIni,
  UMenu,
  UMusic,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenAbout = class(TMenu)
    private
      ShowCreditsRequested: boolean;
      DocumentUI: TDocumentUI;
      function DocumentAction(const Action: UTF8String): boolean;
    public
      TextOverview:    integer;
      procedure ShowCreditsInAbout;
      constructor Create; override;
      destructor Destroy; override;
      function Draw: boolean; override;
      function DrawBG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      procedure OnHide; override;

      procedure SetOverview;
  end;

const
  ID='ID_002';   //for help system

implementation

uses
  UCommon,
  UDataBase,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  USong,
  USongs,
  UUnicodeUtils,
  Classes;

function TScreenAbout.DocumentAction(const Action: UTF8String): boolean;
begin
  Result := true;
  if Action = uiCreditsOpen then Result := ParseInput(SDLK_C, 0, true)
  else if Action = uiNavigationBack then Result := ParseInput(SDLK_ESCAPE, 0, true);
end;

function TScreenAbout.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
begin
  if DocumentUI = nil then Exit(inherited ParseMouse(MouseButton, BtnDown, X, Y));
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then Exit(DocumentAction(uiNavigationBack));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
  else DocumentUI.Mouse(X, Y);
  Result := DocumentAction(DocumentUI.TakeAction);
end;

function TScreenAbout.Draw: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw else Result := inherited Draw;
end;

function TScreenAbout.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited DrawBG;
end;

destructor TScreenAbout.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenAbout.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
begin
  Result := true;
  if (DocumentUI <> nil) and PressedDown then
    case PressedKey of
      SDLK_RETURN: begin DocumentUI.Key(0); Exit(DocumentAction(DocumentUI.TakeAction)); end;
      SDLK_LEFT: begin DocumentUI.Key(-1); Exit; end;
      SDLK_RIGHT: begin DocumentUI.Key(1); Exit; end;
      SDLK_UP: begin DocumentUI.Key(-2); Exit; end;
      SDLK_DOWN: begin DocumentUI.Key(2); Exit; end;
    end;
  if (PressedDown) then
  begin // Key Down
    // check normal keys
    case PressedKey of
      SDLK_C:
        begin
          if not ShowCreditsRequested then
            ShowCreditsInAbout
          else begin
            ShowCreditsRequested := false;
            SetOverview;
          end;
        end;

      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;
    
    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE :
        begin
          Ini.Save;
          AudioPlayback.PlaySound(SoundLib.Back);
          FadeTo(@ScreenMain);
        end;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_RETURN:
        begin
          //Exit Button Pressed
          if Interaction = 1 then
          begin
            AudioPlayback.PlaySound(SoundLib.Back);
            FadeTo(@ScreenMain);
          end;

          // UltraStar Community Edition team credits
          if Interaction = 0 then
          begin
            if not ShowCreditsRequested then
              ShowCreditsInAbout
            else begin
              ShowCreditsRequested := false;
              SetOverview;
            end;
          end;
        end;
      SDLK_LEFT:
      begin
          InteractPrev;
      end;
      SDLK_RIGHT:
      begin
          InteractNext;
      end;
      SDLK_UP:
      begin
          InteractPrev;
      end;
      SDLK_DOWN:
      begin
          InteractNext;
      end;
    end;
  end;
end;

constructor TScreenAbout.Create;
begin
  inherited Create;
  DocumentUI := TDocumentUI.Open('about');
  if DocumentUI <> nil then Exit;

  TextOverview := AddText(Theme.AboutMain.TextOverview);

  LoadFromTheme(Theme.AboutMain);

  AddButton(Theme.AboutMain.ButtonCredits);
  AddButton(Theme.AboutMain.ButtonExit);

  Interaction := 0;
end;

procedure TScreenAbout.OnShow;
begin
  inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenAbout');

  if not ShowCreditsRequested then
    SetOverview;
end;

procedure TScreenAbout.SetOverview;
var
  Overview: UTF8String;
begin
  // Format overview
  Overview := Language.Translate('ABOUT_OVERVIEW');
  if DocumentUI <> nil then DocumentUI.SetValue(uiAboutText, StringReplace(Overview, '\n', #10, [rfReplaceAll]))
  else Text[0].Text := Overview;
end;

procedure TScreenAbout.ShowCreditsInAbout;
var
  S: UTF8String;
  SL: TStringList;
begin
  ShowCreditsRequested := true;
  S := 'Thank you to everyone who contributed to UltraStar Deluxe, including pre-Github contributors: alexanders, blindy, brunzel, canni, hennymcc, jaybinks, krueger, mezzox, mischi, mog, and whiteshark                                                                   Thanks to all our more recent contributors: s09bQ5, basisbit, barbeque-squared, RattleSN4K3, dgruss, AlexanderS, DeinAlptraum, daniel-j, complexlogic, bohning, HermannDppes, TheNailDev, ePirat, brianch, memcopy, kamischi, rhaamo, TheNotary, GaryCXJk, shazzzzam, jose1711, mrtnmtth, sleumas2000, tobijdc, pkerling, mkinoo, ricardosdl, jmfergeau, PonPonTheDreambunny, sarrchri, j-lag, hoehermann, finn-wa, Goostav5, letscodehu, raulmt, luto, douardda, marcszy91, seigneurfuo, DoubleDee73, mobacon, Bronkoknorb, Travisrowe, qamil95, gitter-badger, taligentx, samcarton, and everyone who helped with reporting bugs, testing, translating, creating themes or in any other way!';

  if DocumentUI <> nil then DocumentUI.SetValue(uiAboutText, StringReplace(S, StringOfChar(' ', 67), #10, [rfReplaceAll]));

  // Assign text to the about text control. Some code paths set Text[0],
  // some store the index in TextOverview — update both to be safe.
  if (Length(Text) > 0) then
    Text[0].Text := S;

  if (TextOverview >= 0) and (TextOverview < Length(Text)) then
    Text[TextOverview].Text := S;
end;

procedure TScreenAbout.OnHide;
begin
  inherited;
  ShowCreditsRequested := false;
end;

end.
