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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenMain.pas $
 * $Id: UScreenMain.pas 3128 2015-08-28 01:45:23Z basisbit $
 *}

unit UScreenMain;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UConfig,
  UDisplay,
  UFiles,
  UMenu,
  UMusic,
  UScreenSong,
  USong,
  UThemes,
  MD5,
  sdl2,
  SysUtils;

type

  TScreenMain = class(TMenu)
  private
    Preview: array[0..5] of record
      Statics: array of integer;
      BaseX, BaseAlpha: array of real;
      Alpha: real;
    end;
    PreviewTick: cardinal;
    procedure UpdatePreviews;
  public
    TextDescription:     integer;
    TextDescriptionLong: integer;

    constructor Create; override;
    function ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    procedure OnShow; override;
    procedure SetInteraction(Num: integer); override;
    function Draw: boolean; override;
  end;

const
  ID = 'ID_001';   //for help system

var
  WantSoftwareRenderingMsg: boolean;

implementation

uses
  UGraphic,
  Math,
  URemoteBridgeIPC,
  UHelp,
  UIni,
  ULanguage,
  ULog,
  UNote,
  UParty,
  URenderer,
  USkins,
  USongs,
  UUnicodeUtils;

function TScreenMain.ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean = false): boolean;
var
  SDL_ModState: word;
begin
  Result := true;

  if (PressedDown) then
  begin // Key Down
        // check normal keys
    case PressedKey of
      SDLK_S: begin
        FadeTo(@ScreenName, SoundLib.Start);
        Exit;
      end;

      SDLK_P: begin
        if (Ini.Players >= 1) and (Party.ModesAvailable) then
        begin
          FadeTo(@ScreenPartyOptions, SoundLib.Start);
          Exit;
        end;
      end;

      SDLK_R: begin
        UGraphic.UnLoadScreens();
        Theme.LoadTheme(Ini.Theme, Ini.Color);
        SoundLib.LoadSounds();
        SoundLib.StartBgMusic();
        UGraphic.LoadScreens(Log.Title);
      end;

      SDLK_T: begin
        FadeTo(@ScreenStatMain, SoundLib.Start);
        Exit;
      end;

      SDLK_O: begin
        FadeTo(@ScreenOptions, SoundLib.Start);
        Exit;
      end;

      SDLK_A: begin
        FadeTo(@ScreenAbout, SoundLib.Start);
        Exit;
      end;

      SDLK_C: begin
        ScreenAbout.ShowCreditsInAbout;
        FadeTo(@ScreenAbout, SoundLib.Start);
        Exit;
      end;

      SDLK_Q: begin
        Result := false;
        Exit;
      end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE:
      begin
        Result := false;
      end;

      SDLK_TAB:
      begin
        ScreenPopupHelp.ShowPopup();
      end;

      SDLK_RETURN:
      begin
        // reset
        Party.bPartyGame := false;

        //Solo
        if (Interaction = 0) then
        begin
          if (Songs.SongList.Count >= 1) then
          begin
            PlayersPlay := UIni.IPlayersVals[Ini.Players];

            if Ini.OnSongClick = sSelectPlayer then
              FadeTo(@ScreenSong)
            else
            begin
              ScreenName.Goto_SingScreen := false;
              FadeTo(@ScreenName, SoundLib.Start);
            end;
          end
          else //show error message
            ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_SONGS'));
        end;

        //Party
        if Interaction = 1 then
        begin
          if (Songs.SongList.Count >= 1) then
          begin
            Party.bPartyGame := true;

            FadeTo(@ScreenPartyOptions, SoundLib.Start);
          end
          else //show error message, No Songs Loaded
            ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_SONGS'));
        end;

        if Interaction = 2 then
          FadeTo(@ScreenStatMain, SoundLib.Start);

        if Interaction = 3 then
          FadeTo(@ScreenOptions, SoundLib.Start);
        if Interaction = 4 then
          FadeTo(@ScreenAbout, SoundLib.Start);
        if Interaction = 5 then
          Result := false;
      end;
      {**
       * Up and Down could be done at the same time,
       * but I don't want to declare variables inside
       * functions like this one, called so many times
       *}
      SDLK_DOWN: InteractInc;
      SDLK_UP: InteractDec;
      SDLK_RIGHT: InteractNext;
      SDLK_LEFT: InteractPrev;
    end;
  end
  else // Key Up
    case PressedKey of
      SDLK_RETURN:
      begin
      end;
    end;
end;

function TScreenMain.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
begin
  // default mouse behaviour
  Result := inherited ParseMouse(MouseButton, BtnDown, X, Y);
end;

constructor TScreenMain.Create;
var
  I, J, Index: integer;
begin
  inherited Create;
{**
 * Attention ^^:
 * New Creation Order needed because of LoadFromTheme
 * and Button Collections.
 * At First Custom Texts and Statics
 * Then LoadFromTheme
 * after LoadFromTheme the Buttons and Selects
 *}
  TextDescription     := AddText(Theme.Main.TextDescription);
  TextDescriptionLong := AddText(Theme.Main.TextDescriptionLong);

  LoadFromTheme(Theme.Main);

  for I := 0 to High(Theme.Main.Buttons) do
  begin
    AddButton(Theme.Main.Buttons[I]);
    if Length(Button[High(Button)].Text) > 0 then
      Button[High(Button)].Text[0].Text := Theme.Main.Description[I];
  end;

  AddButton(Theme.Main.ButtonAbout);
  AddButton(Theme.Main.ButtonExit);

  for I := 0 to High(Preview) do
  begin
    SetLength(Preview[I].Statics, Length(Theme.Main.Preview[I]));
    SetLength(Preview[I].BaseX, Length(Theme.Main.Preview[I]));
    SetLength(Preview[I].BaseAlpha, Length(Theme.Main.Preview[I]));
    for J := 0 to High(Preview[I].Statics) do
    begin
      Index := AddStatic(Theme.Main.Preview[I][J]);
      Preview[I].Statics[J] := Index;
      Preview[I].BaseX[J] := Statics[Index].Texture.X;
      Preview[I].BaseAlpha[J] := Statics[Index].Texture.Alpha;
      Statics[Index].Visible := false;
    end;
  end;

  Interaction := 0;

  WantSoftwareRenderingMsg := Renderer.SoftwareRendering;
end;

procedure TScreenMain.OnShow;
var
  I: integer;
begin
  inherited;
  PreviewTick := SDL_GetTicks;
  for I := 0 to High(Preview) do
    Preview[I].Alpha := Ord(I = Interaction);
  RemoteBridgeIPC.SendGameState('main_menu', 0, 0);

  SoundLib.StartBgMusic;

  ScreenSong.Mode := smNormal;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenMains');

 {**
  * Clean up TPartyGame here
  * at the moment there is no better place for this
  *}
  Party.Clear;
end;

procedure TScreenMain.UpdatePreviews;
var
  Now, Elapsed: cardinal;
  I, J, Index: integer;
  Step: real;
begin
  Now := SDL_GetTicks;
  if Now >= PreviewTick then Elapsed := Now - PreviewTick
  else Elapsed := cardinal(QWord(High(cardinal)) - PreviewTick + Now + 1);
  PreviewTick := Now;
  if Theme.Main.PreviewFadeTime > 0 then
    Step := Elapsed / (1000 * Theme.Main.PreviewFadeTime)
  else
    Step := 1;
  for I := 0 to High(Preview) do
  begin
    if I = Interaction then Preview[I].Alpha := Min(1, Preview[I].Alpha + Step)
    else Preview[I].Alpha := Max(0, Preview[I].Alpha - Step);
    for J := 0 to High(Preview[I].Statics) do
    begin
      Index := Preview[I].Statics[J];
      Statics[Index].Visible := Preview[I].Alpha > 0;
      Statics[Index].Texture.Alpha := Preview[I].BaseAlpha[J] * Preview[I].Alpha;
      Statics[Index].Texture.X := Preview[I].BaseX[J] + Theme.Main.PreviewSlideX * (1 - Preview[I].Alpha);
    end;
  end;
end;

function TScreenMain.Draw: boolean;
begin
  UpdatePreviews;
  ScreenSong.ApplyLibraryRefresh;
  Result := inherited Draw;

  if not ScreenPopupError.Visible then
  begin
    if WantSoftwareRenderingMsg then
    begin
      WantSoftwareRenderingMsg := false;
      ScreenPopupError.ShowPopup(Language.Translate('ERROR_SOFTWARE_RENDERING'));
    end;
  end;
end;

procedure TScreenMain.SetInteraction(Num: integer);
begin
  inherited SetInteraction(Num);
  if not Theme.Main.DynamicDescription then Exit;
  Text[TextDescription].Text     := Theme.Main.Description[Interaction];
  Text[TextDescriptionLong].Text := Theme.Main.DescriptionLong[Interaction];
end;

end.
