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
  UDocumentUI,
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
    DocumentUI: TDocumentUI;
    Preview: array[0..5] of record
      Statics: array of integer;
      BaseX, BaseAlpha: array of real;
      Alpha: real;
    end;
    PreviewTick: cardinal;
    function RunAction(const Action: UTF8String): boolean;
    procedure UpdatePreviews;
  public
    TextDescription:     integer;
    TextDescriptionLong: integer;

    constructor Create; override;
    destructor Destroy; override;
    function ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    procedure OnShow; override;
    procedure SetInteraction(Num: integer); override;
    function Draw: boolean; override;
    function DrawBG: boolean; override;
  end;

const
  ID = 'ID_001';   //for help system

var
  WantSoftwareRenderingMsg: boolean;

implementation

uses
  UGraphic,
  Math,
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

function TScreenMain.RunAction(const Action: UTF8String): boolean;
begin
  Result := true;
  if (Action = uiGameSing) or (Action = uiGameParty) then
  begin
    if Songs.SongList.Count = 0 then
    begin
      ScreenPopupError.ShowPopup(Language.Translate('ERROR_NO_SONGS'));
      Exit;
    end;
    if Action = uiGameParty then
    begin
      if (Ini.Players < 1) or not Party.ModesAvailable then Exit;
      Party.bPartyGame := true;
      FadeTo(@ScreenPartyOptions, SoundLib.Start);
    end
    else
    begin
      Party.bPartyGame := false;
      PlayersPlay := UIni.IPlayersVals[Ini.Players];
      if Ini.OnSongClick = sSelectPlayer then FadeTo(@ScreenSong)
      else
      begin
        ScreenName.Goto_SingScreen := false;
        FadeTo(@ScreenName, SoundLib.Start);
      end;
    end;
  end
  else if Action = uiStatisticsOpen then FadeTo(@ScreenStatMain, SoundLib.Start)
  else if Action = uiSettingsOpen then FadeTo(@ScreenOptions, SoundLib.Start)
  else if Action = uiAboutOpen then FadeTo(@ScreenAbout, SoundLib.Start)
  else if Action = uiCreditsOpen then
  begin
    ScreenAbout.ShowCreditsInAbout;
    FadeTo(@ScreenAbout, SoundLib.Start);
  end
  else if Action = uiGameExit then Result := false
  else if Action <> '' then Log.LogWarn('Unknown action: ' + Action, 'ScreenMain');
end;

function TScreenMain.ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean = false): boolean;
const Actions: array[0..5] of UTF8String =
  (uiGameSing, uiGameParty, uiStatisticsOpen, uiSettingsOpen, uiAboutOpen, uiGameExit);
begin
  Result := true;
  if not PressedDown then Exit;
  case PressedKey of
    SDLK_S: Result := RunAction(uiGameSing);
    SDLK_P: Result := RunAction(uiGameParty);
    SDLK_T: Result := RunAction(uiStatisticsOpen);
    SDLK_O: Result := RunAction(uiSettingsOpen);
    SDLK_A: Result := RunAction(uiAboutOpen);
    SDLK_C: Result := RunAction(uiCreditsOpen);
    SDLK_Q, SDLK_ESCAPE, SDLK_BACKSPACE: Result := RunAction(uiGameExit);
    SDLK_TAB: ScreenPopupHelp.ShowPopup();
    SDLK_RETURN:
      if DocumentUI <> nil then
      begin
        DocumentUI.Key(0);
        Result := RunAction(DocumentUI.TakeAction);
      end
      else if (Interaction >= 0) and (Interaction <= High(Actions)) then
        Result := RunAction(Actions[Interaction]);
    SDLK_DOWN, SDLK_RIGHT:
      if DocumentUI <> nil then DocumentUI.Key(1) else InteractNext;
    SDLK_UP, SDLK_LEFT:
      if DocumentUI <> nil then DocumentUI.Key(-1) else InteractPrev;
    SDLK_R:
      begin
        UGraphic.UnLoadScreens();
        Theme.LoadTheme(Ini.Theme, Ini.Color);
        SoundLib.LoadSounds();
        SoundLib.StartBgMusic();
        UGraphic.LoadScreens(Log.Title);
      end;
  end;
end;

function TScreenMain.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
begin
  if DocumentUI = nil then Exit(inherited ParseMouse(MouseButton, BtnDown, X, Y));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
  else DocumentUI.Mouse(X, Y);
  Result := RunAction(DocumentUI.TakeAction);
end;

constructor TScreenMain.Create;
var
  I, J, Index: integer;
begin
  inherited Create;
  DocumentUI := TDocumentUI.Open('main');
  if DocumentUI <> nil then
  begin
    WantSoftwareRenderingMsg := Renderer.SoftwareRendering;
    Exit;
  end;
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

destructor TScreenMain.Destroy;
begin
  DocumentUI.Free;
  inherited;
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
  if DocumentUI <> nil then Result := DocumentUI.Draw
  else
  begin
    UpdatePreviews;
    Result := inherited Draw;
  end;

  if not ScreenPopupError.Visible then
  begin
    if WantSoftwareRenderingMsg then
    begin
      WantSoftwareRenderingMsg := false;
      ScreenPopupError.ShowPopup(Language.Translate('ERROR_SOFTWARE_RENDERING'));
    end;
  end;
end;

function TScreenMain.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true)
  else Result := inherited DrawBG;
end;

procedure TScreenMain.SetInteraction(Num: integer);
begin
  if DocumentUI <> nil then Exit;
  inherited SetInteraction(Num);
  if not Theme.Main.DynamicDescription then Exit;
  Text[TextDescription].Text     := Theme.Main.Description[Interaction];
  Text[TextDescriptionLong].Text := Theme.Main.DescriptionLong[Interaction];
end;

end.
