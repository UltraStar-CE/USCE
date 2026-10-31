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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenOptions.pas $
 * $Id: UScreenOptions.pas 2649 2010-10-10 10:34:20Z tobigun $
 *}

unit UScreenOptions;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UFiles,
  UIni,
  UMenu,
  UDocumentUI,
  UMusic,
  USongs,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenOptions = class(TMenu)
    private
      DocumentUI: TDocumentUI;
      ButtonGameIID,
      ButtonGraphicsIID,
      ButtonSoundIID,
      ButtonInputIID,
      ButtonLyricsIID,
      ButtonThemesIID,
      ButtonRecordIID,
      ButtonAdvancedIID,
      ButtonNetworkIID,
      ButtonWebcamIID,
      ButtonExitIID: cardinal;

      MapIIDtoDescID: array of integer;

      function RunAction(const Action: UTF8String): boolean;
      procedure UpdateTextDescriptionFor(IID: integer); virtual;
      procedure OpenRecordOptions;

    public
      TextDescription:    integer;
      constructor Create; override;
      destructor Destroy; override;
      function Draw: boolean; override;
      function DrawBG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      procedure SetInteraction(Num: integer); override;
  end;

const
  ID='ID_070';   //for help system

implementation

uses
  UDatabase,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UScreenOptionsRecord,
  UWebcam,
  UUnicodeUtils;

procedure TScreenOptions.OpenRecordOptions;
begin
  RefreshAudioInputDevices(aimFull);
  FreeAndNil(ScreenOptionsRecord);
  ScreenOptionsRecord := TScreenOptionsRecord.Create;
  FadeTo(@ScreenOptionsRecord, SoundLib.Start);
end;

function TScreenOptions.RunAction(const Action: UTF8String): boolean;
begin
  Result := true;
  if Action = uiSettingsGame then FadeTo(@ScreenOptionsGame, SoundLib.Start)
  else if Action = uiSettingsGraphics then FadeTo(@ScreenOptionsGraphics, SoundLib.Start)
  else if Action = uiSettingsSound then FadeTo(@ScreenOptionsSound, SoundLib.Start)
  else if Action = uiSettingsInput then FadeTo(@ScreenOptionsInput, SoundLib.Start)
  else if Action = uiSettingsLyrics then FadeTo(@ScreenOptionsLyrics, SoundLib.Start)
  else if Action = uiSettingsThemes then FadeTo(@ScreenOptionsThemes, SoundLib.Start)
  else if Action = uiSettingsRecording then OpenRecordOptions
  else if Action = uiSettingsAdvanced then FadeTo(@ScreenOptionsAdvanced, SoundLib.Start)
  else if Action = uiSettingsNetwork then
  begin
    if High(DataBase.NetworkUser) = -1 then
      ScreenPopupError.ShowPopup(Language.Translate('SING_OPTIONS_NETWORK_NO_DLL'))
    else FadeTo(@ScreenOptionsNetwork, SoundLib.Back);
  end
  else if Action = uiSettingsWebcam then FadeTo(@ScreenOptionsWebcam, SoundLib.Back)
  else if Action = uiNavigationBack then
  begin
    Ini.Save;
    FadeTo(@ScreenMain, SoundLib.Back);
  end
  else if Action = uiGameExit then Result := false
  else if Action <> '' then Log.LogWarn('Unknown action: ' + Action, 'ScreenOptions');
end;

function TScreenOptions.ParseInput(PressedKey: cardinal; CharCode: UCS4Char;
  PressedDown: boolean; Repeated: boolean = false): boolean;
begin
  Result := true;
  if not PressedDown then Exit;
  case PressedKey of
    SDLK_G: Result := RunAction(uiSettingsGame);
    SDLK_H: Result := RunAction(uiSettingsGraphics);
    SDLK_S: Result := RunAction(uiSettingsSound);
    SDLK_I: Result := RunAction(uiSettingsInput);
    SDLK_L: Result := RunAction(uiSettingsLyrics);
    SDLK_T: Result := RunAction(uiSettingsThemes);
    SDLK_R: Result := RunAction(uiSettingsRecording);
    SDLK_A: Result := RunAction(uiSettingsAdvanced);
    SDLK_N: Result := RunAction(uiSettingsNetwork);
    SDLK_W: Result := RunAction(uiSettingsWebcam);
    SDLK_Q: Result := RunAction(uiGameExit);
    SDLK_ESCAPE, SDLK_BACKSPACE: Result := RunAction(uiNavigationBack);
    SDLK_TAB: ScreenPopupHelp.ShowPopup();
    SDLK_RETURN:
      if DocumentUI <> nil then
      begin
        DocumentUI.Key(0);
        Result := RunAction(DocumentUI.TakeAction);
      end
      else
      begin
        if Interaction = ButtonGameIID then Result := RunAction(uiSettingsGame)
        else if Interaction = ButtonGraphicsIID then Result := RunAction(uiSettingsGraphics)
        else if Interaction = ButtonSoundIID then Result := RunAction(uiSettingsSound)
        else if Interaction = ButtonInputIID then Result := RunAction(uiSettingsInput)
        else if Interaction = ButtonLyricsIID then Result := RunAction(uiSettingsLyrics)
        else if Interaction = ButtonThemesIID then Result := RunAction(uiSettingsThemes)
        else if Interaction = ButtonRecordIID then Result := RunAction(uiSettingsRecording)
        else if Interaction = ButtonAdvancedIID then Result := RunAction(uiSettingsAdvanced)
        else if Interaction = ButtonNetworkIID then Result := RunAction(uiSettingsNetwork)
        else if Interaction = ButtonWebcamIID then Result := RunAction(uiSettingsWebcam)
        else if Interaction = ButtonExitIID then Result := RunAction(uiNavigationBack);
      end;
    SDLK_DOWN: if DocumentUI <> nil then DocumentUI.Key(2) else InteractNextRow;
    SDLK_UP: if DocumentUI <> nil then DocumentUI.Key(-2) else InteractPrevRow;
    SDLK_RIGHT: if DocumentUI <> nil then DocumentUI.Key(1) else InteractNext;
    SDLK_LEFT: if DocumentUI <> nil then DocumentUI.Key(-1) else InteractPrev;
  end;
end;

function TScreenOptions.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
begin
  if DocumentUI = nil then Exit(inherited ParseMouse(MouseButton, BtnDown, X, Y));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
  else DocumentUI.Mouse(X, Y);
  Result := RunAction(DocumentUI.TakeAction);
end;

destructor TScreenOptions.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenOptions.Draw: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw
  else Result := inherited Draw;
end;

function TScreenOptions.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true)
  else Result := inherited DrawBG;
end;

constructor TScreenOptions.Create;

  // TODO: Generalize method and implement it into base code (to be used by every screen/menu)
  function AddButtonChecked(Btn: TThemeButton; DescIndex: byte; out IIDvar: cardinal; AddX: real = 14; AddY: real = 20): cardinal;
  var OldPos: integer;
  begin
    OldPos := Length(Button);
    Result := AddButton(Btn);
    if Length(Button) <> OldPos then // check if button was succesfully added // TODO: RattleSN4K3: Improve AddButton interface returning properly index to be used by interaction check
    begin
      IIDvar := High(Interactions);

      // update mapping, IID to Desc index
      SetLength(MapIIDtoDescID, IIDvar+1);
      MapIIDtoDescID[IIDvar] := DescIndex;

      if (Length(Button[Result].Text) = 0) then // update text if not already set
        AddButtonText(AddX, AddY, Theme.Options.Description[DescIndex]);
    end;

  end;
begin
  inherited Create;

  DocumentUI := TDocumentUI.Open('settings');
  if DocumentUI <> nil then Exit;

  TextDescription := AddText(Theme.Options.TextDescription);

  LoadFromTheme(Theme.Options);

  // Order is irrelevant to the represenatation, however InteractNext/Prev is not working with a different order // TODO: RattleSN4K3: allow InteractNext etc. work with themes having a different button layout
  AddButtonChecked(Theme.Options.ButtonGame, OPTIONS_DESC_INDEX_GAME,  ButtonGameIID);
  AddButtonChecked(Theme.Options.ButtonGraphics, OPTIONS_DESC_INDEX_GRAPHICS,  ButtonGraphicsIID);
  AddButtonChecked(Theme.Options.ButtonSound, OPTIONS_DESC_INDEX_SOUND,  ButtonSoundIID);
  AddButtonChecked(Theme.Options.ButtonInput, OPTIONS_DESC_INDEX_INPUT,  ButtonInputIID);

  AddButtonChecked(Theme.Options.ButtonLyrics, OPTIONS_DESC_INDEX_LYRICS,  ButtonLyricsIID);
  AddButtonChecked(Theme.Options.ButtonThemes, OPTIONS_DESC_INDEX_THEMES,  ButtonThemesIID);
  AddButtonChecked(Theme.Options.ButtonRecord, OPTIONS_DESC_INDEX_RECORD,  ButtonRecordIID);
  AddButtonChecked(Theme.Options.ButtonAdvanced, OPTIONS_DESC_INDEX_ADVANCED,  ButtonAdvancedIID);
  AddButtonChecked(Theme.Options.ButtonNetwork, OPTIONS_DESC_INDEX_NETWORK,  ButtonNetworkIID);

  AddButtonChecked(Theme.Options.ButtonWebcam, OPTIONS_DESC_INDEX_WEBCAM,  ButtonWebcamIID);

  AddButtonChecked(Theme.Options.ButtonExit, OPTIONS_DESC_INDEX_BACK,  ButtonExitIID);

  Interaction := 0;
end;

procedure TScreenOptions.OnShow;
begin
  inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenOptions');

  // continue possibly stopped bg-music (stopped in record options)
  SoundLib.StartBgMusic;
end;

procedure TScreenOptions.SetInteraction(Num: integer);
begin
  if DocumentUI <> nil then Exit;
  inherited SetInteraction(Num);
  UpdateTextDescriptionFor(Interaction);
end;

procedure TScreenOptions.UpdateTextDescriptionFor(IID: integer);
begin
  if DocumentUI <> nil then Exit;
  // Sanity check
  if (IID < 0 ) or (IID >= Length(MapIIDtoDescID)) then
    Exit;

  Text[TextDescription].Text := Theme.Options.Description[MapIIDtoDescID[IID]];
end;

end.
