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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenName.pas $
 * $Id: UScreenName.pas 1939 2009-11-09 00:27:55Z s_alexander $
 *}

unit UScreenName;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UPlayerLayout,
  UVoiceAssignments,
  UAvatars,
  UDisplay,
  UFiles,
  UIni,
  UMenu,
  UMenuInteract,
  UMusic,
  UMenuSelectSlide,
  URecord,
  UNote,
  UScreenScore,
  UScreenSingController,
  UScreenHighScores,
  UScale,
  USlotDelayMeasurement,
  UThemes,
  SysUtils,
  sdl2,
  md5;

type
  TSetupMicChannel = record
    DeviceIndex, ConfigIndex, Channel: integer;
    DeviceName: UTF8String;
  end;

  TScreenName = class(TMenu)
    private
      PlayersCount:  cardinal;
      PlayersCountIID: integer;
      PlayerAvatar:  cardinal;
      PlayerName:    cardinal;
      PlayerNameIID: integer;
      PlayerColor:   cardinal;
      PlayerColorIID: integer;
      PlayerSelect:  cardinal;
      PlayerSelectIID: integer;
      PlayerSelectLevel: cardinal;
      PlayerSelectLevelIID: integer;
      PlayerSelectVoice: cardinal;
      PlayerSelectVoiceIID: integer;
      VoiceIndex: integer;

      CountIndex:   integer;
      ConfirmedLocalPlayerCount: integer;
      LyricsOnly: boolean;
      RemoteSlots: cardinal;
      AvailableChannels: integer;
      PlayerMic, PlayerMicIID, MicOption: integer;
      MicDevicesScanned: boolean;
      PlayerIndex:  integer;
      ColorIndex:   integer;
      LevelIndex:   integer;

      PlayerAvatarIID: integer; // interaction ID

      AvatarCurrent: real;
      AvatarTarget:  integer;

      NumVisibleAvatars:      integer;
      DistanceVisibleAvatars: integer;

      isScrolling: boolean;   // true if avatar flow is about to move

      PlayerCurrent:       array [0..UIni.IMaxPlayerCount-1] of integer;
      PlayerCurrentText:   array [0..UIni.IMaxPlayerCount-1] of integer;
      PlayerCurrentAvatar: array [0..UIni.IMaxPlayerCount-1] of integer;

      PlayerNames:   array [0..UIni.IMaxPlayerCount-1] of UTF8String;
      PlayerAvatars: array [0..UIni.IMaxPlayerCount-1] of integer;
      PlayerLevel:   array [0..UIni.IMaxPlayerCount-1] of integer;

      APlayerColor: array of integer;

      PlayerAvatarButton: array of integer;
      CardPanel, CardFocus, MicFrame: integer;
      MicPreviewCount, MicPreviewLocalCount: integer;
      OwnsMicPreview: boolean;
      DelayMeasurement: TSlotDelayMeasurement;
      DelayPausedBgMusic: boolean;
      DelayHintText, DelayApplyButton, DelayCancelButton: integer;
      MicActivity: array[0..UIni.IMaxPlayerCount-1] of single;
      MicClippedUntil: array[0..UIni.IMaxPlayerCount-1] of QWord;
      MicPickerPlayer, MicPickerOwner: integer;
      MicPickerChoices: array of TSetupMicChannel;
      PendingMic: TSetupMicChannel;
      function AddDelayButton(const Style: TThemeButton; const Key: UTF8String): integer;
      procedure DrawDelayButton(Index: integer);
      function DelaySlots: cardinal;
      procedure StartDelayMeasurement;
      procedure CloseDelayMeasurement;
      procedure DrawDelayMeasurement;
      procedure ApplyDelayMeasurement;
      procedure RefreshMicSelector;
      function ScanMicDevices: boolean;
      procedure ChangeMic(Delta: integer);
      function CurrentMicChoiceValid: boolean;
      procedure ApplyMicChoice;
      function BuildMicChoices: integer;
      function HighestRemoteSlot: integer;
      function InlineCardMic: boolean;
      function CardEditorScaleY(PlayerID: integer; const Card: TPlayerSlotRect): real;
      procedure LayoutMicSelector;
      procedure DrawMicSelector;
      procedure UpdateAssignedPlayers(Force: boolean = false);
      function DisplayPlayerName(Index: integer): UTF8String;
      function IsRosterGap(Index: integer): boolean;
      procedure UpdateMicActivity;
      function MicColor(PlayerID: integer): TRGB;
      function SelectedPlayerCount: integer;
      function SelectedLocalPlayerCount: integer;
      function CardRect(Index: integer): TPlayerSlotRect;
      function DifficultySegmentRect(PlayerID, Segment: integer): TMouseOverRect;
      procedure DrawCards;
      procedure RefreshVoice;
    public
      Goto_SingScreen: boolean; //If true then next Screen in SingScreen

      constructor Create; override;
      destructor Destroy; override;
      function ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;

      procedure SetInteraction(Num: integer); override;
      procedure OnShow; override;
      procedure OnHide; override;
      function Draw: boolean; override;

      procedure SetAvatarScroll;
      procedure SelectNext;
      procedure SelectPrev;

      procedure PlayerColorButton(K: integer);
      function NoRepeatColors(ColorP: integer; Interaction: integer; Pos: integer):integer;
      function ActivePlayerCount: integer;
      function DelayMeasurementOpen: boolean;
      function LocalPlayerCount: integer;
      procedure RefreshPlayers();
      procedure RefreshProfile();
      procedure RefreshColor();

      procedure ChangeSelectPlayerPosition(Player: integer);

      procedure GenerateAvatars();
      procedure SetPlayerAvatar(Player: integer);
      procedure LoadPlayersFromIni(LoadAvatars: boolean = true);
      procedure ApplyPlayerSelectLayout(Player, PlayerCount: integer);
  end;

var
  Num: array[0..UIni.IMaxPlayerCount-1]of integer;

const
  ID='ID_010';   //for help system

implementation

uses

  UAudioCalibration,
  UText,
  UParty,
  URemoteBridgeIPC,
  URemoteInput,
  UInputSource,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UMain,
  UMenuButton,
  UPath,
  URenderer,
  UScreenSong,
  UContinuousPlayback,
  USkins,
  USongs,
  UTime,
  UUnicodeUtils,
  Math;

const
  MicPreviewFreshMs = 250;
  MicClipHoldMs = 500;
  LyricsOnlyIndex = 0;
  PhonesOnlyIndex = 1;

function GetNamePlayerSelectBaseBounds: TPlayerSlotRect;
begin
  Result := UThemes.GetNamePlayerSelectBaseBounds(Theme.Name);
end;

function GetNamePlayerSelectLayoutBounds(const BaseBounds: TPlayerSlotRect; PlayerCount: integer): TPlayerSlotRect;
begin
  Result := UThemes.GetNamePlayerSelectLayoutBounds(BaseBounds, Theme.Name.PlayerSelectLayout);
end;

function GetNamePlayerSelectSlotRect(PlayerIndex, PlayerCount: integer; const BaseBounds, LayoutBounds: TPlayerSlotRect): TPlayerSlotRect;
begin
  Result := UThemes.GetNamePlayerSelectSlotRect(PlayerIndex, PlayerCount, BaseBounds, LayoutBounds, Theme.Name.PlayerSelectLayout);
end;

function ScaleNameCoord(const Value, SourceStart, SourceSize, TargetStart, TargetSize: integer): integer;
begin
  Result := ScaleCoordToSlot(Value, SourceStart, SourceSize, TargetStart, TargetSize);
end;

function ScaleNameLength(const Value, SourceSize, TargetSize: integer): integer;
begin
  Result := ScaleLengthToSlot(Value, SourceSize, TargetSize);
end;

function GetNamePlayerSelectFittedRect(PlayerIndex, PlayerCount: integer): TPlayerSlotRect;
var
  BaseBounds: TPlayerSlotRect;
  LayoutBounds: TPlayerSlotRect;
  SlotRect: TPlayerSlotRect;
  MaxScale: real;
begin
  BaseBounds := GetNamePlayerSelectBaseBounds;
  LayoutBounds := GetNamePlayerSelectLayoutBounds(BaseBounds, PlayerCount);
  SlotRect := GetNamePlayerSelectSlotRect(PlayerIndex, PlayerCount, BaseBounds, LayoutBounds);

  MaxScale := UThemes.GetNamePlayerSelectMaxScale(PlayerCount, Theme.Name.PlayerSelectLayout);

  Result := GetFittedSlotRect(BaseBounds, SlotRect, MaxScale);
end;

procedure TScreenName.SetInteraction(Num: integer);
begin
  if (Num <> SelInteraction) and (PlayerName < cardinal(Length(Button))) and
    (Length(Button[PlayerName].Text) > 0) and Button[PlayerName].Selected then
  begin
    Button[PlayerName].Text[0].AcceptNameSuggestion;
    PlayerNames[PlayerIndex] := Button[PlayerName].Text[0].Text;
  end;
  inherited SetInteraction(Num);
end;

function TScreenName.DifficultySegmentRect(PlayerID, Segment: integer): TMouseOverRect;
var R: TPlayerSlotRect; SX, SY, SegmentW: real;
begin
  R := CardRect(PlayerID);
  SX := R.W / Max(1, Theme.Name.Cards.Panel.W);
  SY := CardEditorScaleY(PlayerID, R);
  if (PlayerID = PlayerIndex) and Theme.Name.Cards.EditOutside then
  begin
    R.X := 0; R.Y := 0; SX := 1; SY := 1;
  end;
  SegmentW := (Theme.Name.Cards.Panel.W - 30) / 3;
  Result.X := R.X + (Theme.Name.SelectPlayerLevel.X + Segment * SegmentW) * SX;
  Result.Y := R.Y + Theme.Name.SelectPlayerLevel.Y * SY;
  Result.W := (SegmentW - 4) * SX;
  Result.H := 29 * SY;
end;

function TScreenName.ScanMicDevices: boolean;
begin
  Result := not MicDevicesScanned and not Party.bPartyGame and not AudioInput.IsCapturing;
  if not Result then Exit;
  MicDevicesScanned := true;
  // Startup only probes assigned microphones. Include free channels in setup.
  RefreshAudioInputDevices(aimFull);
end;

procedure ConfirmSetupMicMove(Confirmed: boolean; Data: Pointer);
begin
  if Confirmed then TScreenName(Data).ApplyMicChoice;
end;

function TScreenName.BuildMicChoices: integer;
var
  D, C, N, ConfigIndex: integer;
  Device: TAudioInputDevice;
begin
  MicPickerChoices := nil;
  Result := -1;
  for D := 0 to High(AudioInputProcessor.DeviceList) do
  begin
    Device := AudioInputProcessor.DeviceList[D];
    if Device = nil then Continue;
    ConfigIndex := Device.CfgIndex;
    if (ConfigIndex < 0) or (ConfigIndex > High(Ini.InputDeviceConfig)) then Continue;
    for C := 0 to Min(Device.AudioFormat.Channels,
        Length(Ini.InputDeviceConfig[ConfigIndex].ChannelToPlayerMap)) - 1 do
    begin
      N := Length(MicPickerChoices);
      SetLength(MicPickerChoices, N + 1);
      MicPickerChoices[N].DeviceIndex := D;
      MicPickerChoices[N].ConfigIndex := ConfigIndex;
      MicPickerChoices[N].DeviceName := Device.Name;
      MicPickerChoices[N].Channel := C;
      if Ini.InputDeviceConfig[ConfigIndex].ChannelToPlayerMap[C] = PlayerIndex + 1 then
        Result := N;
    end;
  end;
end;

procedure TScreenName.RefreshMicSelector;
var
  Choice: integer;
  Caption: UTF8String;
begin
  SelectsS[PlayerMic].Visible := not Party.bPartyGame and (SelectedPlayerCount > 0);
  if not SelectsS[PlayerMic].Visible then Exit;
  Choice := BuildMicChoices;
  if RemoteInputProcessor.HasAssignedPlayer(PlayerIndex) then
    Caption := Language.Translate('SING_SETUP_MIC_PHONE')
  else if (PlayerIndex >= SelectedLocalPlayerCount) or (Choice < 0) then
    Caption := Language.Translate('SING_OPTIONS_RECORD_NOONE')
  else
    with MicPickerChoices[Choice] do
      Caption := Format(Language.Translate('SING_SETUP_MIC_CHOICE'), [Channel + 1, DeviceName]);
  MicOption := 0;
  UpdateSelectSlideOptions(PlayerMic,
    [Language.Translate('SING_SETUP_MIC_LABEL') + ' ' + Caption], MicOption);
end;

procedure TScreenName.ChangeMic(Delta: integer);
var I, Current, Choice: integer;
begin
  if (PlayerIndex >= SelectedLocalPlayerCount) or RemoteInputProcessor.HasAssignedPlayer(PlayerIndex) then Exit;
  Current := BuildMicChoices;
  if Length(MicPickerChoices) = 0 then Exit;
  // Keep browsing from a declined proposal if the same channel still exists.
  if MicPickerPlayer = PlayerIndex then
    for I := 0 to High(MicPickerChoices) do
      with MicPickerChoices[I] do
        if (DeviceIndex = PendingMic.DeviceIndex) and
           (ConfigIndex = PendingMic.ConfigIndex) and
           (DeviceName = PendingMic.DeviceName) and (Channel = PendingMic.Channel) then
        begin
          Current := I;
          Break;
        end;
  if Current < 0 then
  begin
    if Delta > 0 then Choice := 0
    else Choice := High(MicPickerChoices);
  end
  else
    Choice := (Current + Delta + Length(MicPickerChoices)) mod Length(MicPickerChoices);
  MicPickerPlayer := PlayerIndex;
  PendingMic := MicPickerChoices[Choice];
  with PendingMic do
    MicPickerOwner := Ini.InputDeviceConfig[ConfigIndex].ChannelToPlayerMap[Channel];
  if (MicPickerOwner <> CHANNEL_OFF) and (MicPickerOwner <> PlayerIndex + 1) then
    ScreenPopupCheck.ShowPopup(Format(Language.Translate('SING_SETUP_MIC_MOVE'),
      [MicPickerOwner]), @ConfirmSetupMicMove, Self)
  else
    ApplyMicChoice;
end;

function TScreenName.CurrentMicChoiceValid: boolean;
var
  Device: TAudioInputDevice;
begin
  Result := false;
  with PendingMic do
  begin
    if (DeviceIndex < 0) or (DeviceIndex > High(AudioInputProcessor.DeviceList)) or
        (ConfigIndex < 0) or (ConfigIndex > High(Ini.InputDeviceConfig)) then Exit;
    Device := AudioInputProcessor.DeviceList[DeviceIndex];
    if (Device = nil) or (Device.CfgIndex <> ConfigIndex) or (Device.Name <> DeviceName) then Exit;
    Result := (Channel < Device.AudioFormat.Channels) and
      (Channel <= High(Ini.InputDeviceConfig[ConfigIndex].ChannelToPlayerMap));
  end;
end;

procedure TScreenName.ApplyMicChoice;
var
  D, C, Player: integer;
begin
  if not CurrentMicChoiceValid or (MicPickerPlayer >= SelectedLocalPlayerCount) or
    RemoteInputProcessor.HasAssignedPlayer(MicPickerPlayer) then Exit;
  with PendingMic do
  begin
    if Ini.InputDeviceConfig[ConfigIndex].ChannelToPlayerMap[Channel] <> MicPickerOwner then
      Exit;
    if OwnsMicPreview then AudioInput.CaptureStop(true);
    OwnsMicPreview := false;
    MicPreviewCount := -1;
    Player := MicPickerPlayer + 1;
    for D := 0 to High(Ini.InputDeviceConfig) do
      for C := 0 to High(Ini.InputDeviceConfig[D].ChannelToPlayerMap) do
        if Ini.InputDeviceConfig[D].ChannelToPlayerMap[C] = Player then
          Ini.InputDeviceConfig[D].ChannelToPlayerMap[C] := CHANNEL_OFF;
    Ini.InputDeviceConfig[ConfigIndex].ChannelToPlayerMap[Channel] := Player;
  end;
  MicPickerPlayer := -1;
  Ini.SaveRecordingAssignments;
  RefreshMicSelector;
end;

function TScreenName.InlineCardMic: boolean;
begin
  Result := Theme.Name.Cards.Enabled and not Theme.Name.Cards.EditOutside and
    Theme.Name.AutoPlacePlayerMic and SelectsS[PlayerMic].Visible;
end;

function TScreenName.CardEditorScaleY(PlayerID: integer; const Card: TPlayerSlotRect): real;
var Height: integer;
begin
  Height := Card.H;
  if (PlayerID = PlayerIndex) and InlineCardMic then
    Height := Max(1, Height - Round(SelectsS[PlayerMic].H) - 8);
  Result := Height / Max(1, Theme.Name.Cards.Panel.H);
end;

procedure TScreenName.LayoutMicSelector;
const
  Gap = 4;
  FooterSpace = 55;
  CardPadding = 15;
var
  Anchor: TPlayerSlotRect;
  Avatar: TThemeButton;
  I: integer;
  RightEdge, MicX, MicY, Width, Bottom: single;
begin
  if not Theme.Name.AutoPlacePlayerMic then Exit;

  if InlineCardMic then
  begin
    Anchor := CardRect(PlayerIndex);
    MicX := Anchor.X + CardPadding;
    MicY := Anchor.Y + Anchor.H - SelectsS[PlayerMic].H - Gap;
    Width := Max(1, Anchor.W - 2 * CardPadding);
  end
  else
  begin
    with SelectsS[PlayerSelectLevel].TextureSBG do
    begin
      Anchor.X := Round(X);
      Anchor.Y := Round(Y);
      Anchor.W := Round(W);
      Anchor.H := Round(H);
    end;
    if (Anchor.W < 40) or (Anchor.X >= RenderW) or (Anchor.Y >= RenderH) then
      with Theme.Name.PlayerButtonName do
      begin
        Anchor.X := X;
        Anchor.Y := Y;
        Anchor.W := W;
        Anchor.H := H;
      end;
    Bottom := Anchor.Y + Anchor.H;
    if SelectsS[PlayerSelectVoice].Visible then
      with SelectsS[PlayerSelectVoice].TextureSBG do
        Bottom := Max(Bottom, Y + H);

    Width := EnsureRange(Anchor.W, 170, 260);
    MicX := Anchor.X;
    MicY := Bottom + Gap;
    if MicY + SelectsS[PlayerMic].H > RenderH - FooterSpace then
    begin
      MicX := Anchor.X + Anchor.W + Gap;
      MicY := Anchor.Y + (Anchor.H - SelectsS[PlayerMic].H) / 2;
      RightEdge := RenderW - Gap;
      Avatar := Theme.Name.PlayerButtonAvatar;
      if (Avatar.X > MicX) and (Avatar.Y < MicY + SelectsS[PlayerMic].H) and
         (Avatar.Y + Avatar.H > MicY) then
        RightEdge := Min(RightEdge, Avatar.X - Gap);
      if RightEdge - MicX >= 120 then
        Width := Min(Width, RightEdge - MicX);
    end;
  end;
  with SelectsS[PlayerMic] do
  begin
    if not SameValue(SBGW, Width) then
    begin
      SBGW := Width;
      SetSelectOpt(SelectedOption);
    end;
    SetX(EnsureRange(MicX, Gap, RenderW - Width - Gap));
    SetY(MicY);
    for I := 0 to High(TextOpt) do
      TextOpt[I].X := TextureSBG.X + TextureSBG.W / 2;
  end;
end;

procedure TScreenName.DrawMicSelector;
var
  Level: single;
begin
  if not SelectsS[PlayerMic].Visible then Exit;
  LayoutMicSelector;
  with SelectsS[PlayerMic] do
  begin
    if (Length(MicPickerChoices) > 0) and (PlayerIndex < SelectedLocalPlayerCount) and
       not RemoteInputProcessor.HasAssignedPlayer(PlayerIndex) then
    begin
      Tex_SelectS_ArrowL.Alpha := 1;
      Tex_SelectS_ArrowR.Alpha := 1;
    end;
    Draw;
  end;
  Level := EnsureRange(MicActivity[PlayerIndex], 0, 1);
  with SelectsS[PlayerMic].TextureSBG do
    Renderer.DrawQuad(X, Y + H - 2, 0, W * Level, 2, 1, 1, 1, 0.9);
end;

function TScreenName.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  I: integer;
  Btn: integer;
  MouseX, MouseY: integer;
  Card: TPlayerSlotRect;
  SegmentBounds: TMouseOverRect;
begin
  Result := true;

  MouseX := X;
  MouseY := Y;
  // transfer mousecords to the 800x600 raster we use to draw
  X := Round((X / (ScreenW / Screens)) * RenderW);
  if (X > RenderW) then
    X := X - RenderW;
  Y := Round((Y / ScreenH) * RenderH);
  if Assigned(DelayMeasurement) then
  begin
    if BtnDown and (MouseButton = SDL_BUTTON_LEFT) then
      if InRegion(X, Y, Button[DelayCancelButton].GetMouseOverArea) then
        CloseDelayMeasurement
      else if InRegion(X, Y, Button[DelayApplyButton].GetMouseOverArea) then
        ApplyDelayMeasurement;
    Exit;
  end;
  if BtnDown and (MouseButton = SDL_BUTTON_LEFT) and SelectsS[PlayerMic].Visible and
     InRegion(X, Y, SelectsS[PlayerMic].GetMouseOverArea) then
  begin
    Interaction := PlayerMicIID;
    StopTextInput;
    case SelectsS[PlayerMic].OnClick(X, Y) of
      maLeft: ChangeMic(-1);
      maRight: ChangeMic(1);
    end;
    Exit;
  end;
  if Theme.Name.Cards.Enabled and (SelectedPlayerCount > 0) and
     BtnDown and (MouseButton = SDL_BUTTON_LEFT) then
  begin
    if Theme.Name.Cards.LevelSegments then
      for I := 0 to 2 do
      begin
        SegmentBounds := DifficultySegmentRect(PlayerIndex, I);
        if (X >= SegmentBounds.X) and (X <= SegmentBounds.X + SegmentBounds.W) and
          (Y >= SegmentBounds.Y) and (Y <= SegmentBounds.Y + SegmentBounds.H) then
        begin
          LevelIndex := I;
          PlayerLevel[PlayerIndex] := I;
          SelectsS[PlayerSelectLevel].SetSelectOpt(I);
          Interaction := PlayerSelectLevelIID;
          SetTextInput(false);
          Exit;
        end;
      end;
    Btn := InteractAt(X, Y);
    // Selecting a card editor must not generate the menu's Return action.
    // This also covers themes that place the name editor outside the card.
    if (Btn = PlayerNameIID) or (Btn = PlayerAvatarIID) then
    begin
      Interaction := Btn;
      SetTextInput(Button[PlayerName].Selected);
      Exit;
    end;
    for I := 0 to SelectedPlayerCount - 1 do
      if I div (Theme.Name.Cards.Columns * Theme.Name.Cards.Rows) = PlayerIndex div (Theme.Name.Cards.Columns * Theme.Name.Cards.Rows) then
      begin
        Card := CardRect(I);
        if (X >= Card.X) and (X <= Card.X + Card.W) and
          (Y >= Card.Y) and (Y <= Card.Y + Card.H) then
        begin
          if I <> PlayerIndex then
          begin
            PlayerNames[PlayerIndex] := Button[PlayerName].Text[0].Text;
            PlayerIndex := I;
            AvatarTarget := PlayerAvatars[PlayerIndex];
            AvatarCurrent := AvatarTarget;
            RefreshProfile;
            if Button[PlayerName].Selectable then Interaction := PlayerNameIID
            else Interaction := PlayerSelectIID;
          end
          else if (Btn = PlayerColorIID) or (Btn = PlayerSelectLevelIID) or
            (Btn = PlayerSelectVoiceIID) then
          begin
            // Slides retain their normal click/arrow handling.
            inherited ParseMouse(MouseButton, BtnDown, MouseX, MouseY);
          end;
          SetTextInput(Button[PlayerName].Selected);
          Exit;
        end;
      end;
  end;
  inherited ParseMouse(MouseButton, BtnDown, MouseX, MouseY);
  SetTextInput(Button[PlayerName].Selected);
  if (BtnDown) then
  begin
     //if RightMbESC is set, send ESC keypress
    if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) then
      Result:=ParseInput(SDLK_ESCAPE, 0, true);

    //scrolling avatars with mousewheel
    if (MouseButton = SDL_BUTTON_WHEELDOWN) then
    begin
      if (Interaction = PlayerAvatarIID) then
        ParseInput(SDLK_RIGHT, 0, true);
    end
    else if (MouseButton = SDL_BUTTON_WHEELUP) then
    begin
      if (Interaction = PlayerAvatarIID) then
        ParseInput(SDLK_LEFT, 0, true);
    end
    else
    begin
      // click avatars
      // 1st left
      Btn := AvatarTarget - 2;
      if (Btn < 0) then
        Btn := High(AvatarsList);

      if InRegion(X, Y, Button[PlayerAvatarButton[Btn]].GetMouseOverArea) then
      begin
        Interaction := PlayerAvatarIID;

        ParseInput(SDLK_LEFT, 0, true);
        ParseInput(SDLK_LEFT, 0, true);
      end;

      // 2nd left
      Btn := AvatarTarget - 1;
      if (Btn < 0) then
        Btn := High(AvatarsList);

      if InRegion(X, Y, Button[PlayerAvatarButton[Btn]].GetMouseOverArea) then
      begin
        Interaction := PlayerAvatarIID;

        ParseInput(SDLK_LEFT, 0, true);
      end;

      // 1st right
      Btn := AvatarTarget + 1;
      if (Btn > High(AvatarsList)) then
        Btn := 0;

      if InRegion(X, Y, Button[PlayerAvatarButton[Btn]].GetMouseOverArea) then
      begin
        Interaction := PlayerAvatarIID;

        ParseInput(SDLK_RIGHT, 0, true);
      end;

      // 2nd right
      Btn := AvatarTarget + 2;
      if (Btn > High(AvatarsList)) then
        Btn := 0;

      if InRegion(X, Y, Button[PlayerAvatarButton[Btn]].GetMouseOverArea) then
      begin
        Interaction := PlayerAvatarIID;

        ParseInput(SDLK_RIGHT, 0, true);
        ParseInput(SDLK_RIGHT, 0, true);
      end;

      // click for change player profile
      for I := 0 to High(PlayerCurrent) do
      begin
        if Statics[PlayerCurrent[I]].Visible and InRegion(X, Y, Statics[PlayerCurrent[I]].GetMouseOverArea) then
        begin
          Interaction := PlayerSelectIID;
          PlayerIndex := I;

          RefreshProfile();

          isScrolling := true;
          AvatarTarget := PlayerAvatars[PlayerIndex];
        end;
      end;
    end;
  end;
end;

function TScreenName.ShouldHandleInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; out SuppressKey: boolean): boolean;
begin
  Result := inherited;
  // only suppress special keys for now
  if GetNameTemplateIndexFromKey(PressedKey) <> -1 then
    if (Button[PlayerName].Selected) then
      SuppressKey := true
    else
      Result := false;
end;

function TScreenName.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
  var
    I: integer;
    SDL_ModState: word;

  procedure HandleNameTemplate(const index: integer);
  var
    isAlternate: boolean;
  begin
    isAlternate := (SDL_ModState = KMOD_LSHIFT) or (SDL_ModState = KMOD_RSHIFT);
    isAlternate := isAlternate or (SDL_ModState = KMOD_LALT); // legacy key combination

    if isAlternate then
    begin
      Ini.NameTemplate[index] := Button[PlayerName].Text[0].Text;
    end
    else
    begin
      Button[PlayerName].Text[0].Text := Ini.NameTemplate[index];
      PlayerNames[PlayerIndex] := Button[PlayerName].Text[0].Text;
    end;
  end;

  procedure HandleTemplateHotkey;
  var
    TemplateIndex: integer;
  begin
    TemplateIndex := GetNameTemplateIndexFromKey(PressedKey);
    if (TemplateIndex >= 0) and (TemplateIndex <= High(Ini.NameTemplate)) then
      HandleNameTemplate(TemplateIndex);
  end;

begin
  Result := true;
  if (PressedDown) then
  begin // Key Down
    if Assigned(DelayMeasurement) then
    begin
      if not Repeated then
        case PressedKey of
          SDLK_ESCAPE: CloseDelayMeasurement;
          SDLK_RETURN, SDLK_KP_ENTER: ApplyDelayMeasurement;
        end;
      Exit;
    end;
    if (PressedKey = SDLK_M) and ((SDL_GetModState and KMOD_CTRL) <> 0) then
    begin
      if not Repeated then StartDelayMeasurement;
      Exit;
    end;
    if (PressedKey = SDLK_I) and ((SDL_GetModState and KMOD_CTRL) <> 0) and
        not Party.bPartyGame and (SelectedPlayerCount > 0) then
    begin
      if not Repeated then Interaction := PlayerMicIID;
      Exit;
    end;
    if HandleNameSuggestionKey(PressedKey) then
    begin
      PlayerNames[PlayerIndex] := Button[PlayerName].Text[0].Text;
      Exit;
    end;

    SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
    + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT);

    if (not Button[PlayerName].Selected) then
    begin
      // check normal keys
      case PressedKey of
        SDLK_Q:
          begin
            Result := false;
            Exit;
          end;
      end;
    end
    else if (Interaction = PlayerNameIID) and (IsPrintableChar(CharCode)) then
    begin
      // pass printable chars to button
      Button[PlayerName].Text[0].TypeNameCharacter(UCS4ToUTF8String(CharCode));

      PlayerNames[PlayerIndex] := Button[PlayerName].Text[0].Text;
      Exit;
    end;

    // check special keys
    case PressedKey of

      SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6,
      SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11, SDLK_F12:
        HandleTemplateHotkey;

      SDLK_BACKSPACE:
        begin
          if (Interaction = PlayerNameIID) then
          begin
            Button[PlayerName].Text[0].DeleteNameCharacter;
            PlayerNames[PlayerIndex] := Button[PlayerName].Text[0].Text;
          end
          else
            ParseInput(SDLK_ESCAPE, CharCode, PressedDown);
        end;

      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;

      SDLK_ESCAPE :
        begin
          if ScreenContinuousPlayback.WaitingForPlayers then
          begin ScreenContinuousPlayback.Stop; Exit; end;
          StopTextInput;
          Ini.SaveNames;
          AudioPlayback.PlaySound(SoundLib.Back);
          if GoTo_SingScreen then
          begin
            ScreenSong.PreservePreviewForReturn;
            FadeTo(@ScreenSong);
            GoTo_SingScreen := false;
          end
          else
            FadeTo(@ScreenMain);
        end;

      SDLK_RETURN:
        begin
          StopTextInput;
          UpdateAssignedPlayers;
          if not Party.bPartyGame then
          begin
            if (CountIndex = PhonesOnlyIndex) and (HighestRemoteSlot = 0) then
            begin
              Interaction := PlayersCountIID;
              ScreenPopupError.ShowPopup(Language.Translate('SING_SETUP_NO_PHONE_MIC'));
              Exit;
            end;
            for I := 0 to SelectedLocalPlayerCount - 1 do
              if PlayerInputSource(I, SelectedLocalPlayerCount) = pisNone then
              begin
                PlayerIndex := I;
                RefreshProfile;
                Interaction := PlayerMicIID;
                ScreenPopupError.ShowPopup(Format(
                  Language.Translate('ERROR_PLAYER_NO_DEVICE_ASSIGNMENT'), [I + 1]));
                Exit;
              end;
            ConfirmedLocalPlayerCount := SelectedLocalPlayerCount;
            LyricsOnly := CountIndex = LyricsOnlyIndex;
            if not LyricsOnly then Ini.SetupLocalPlayers := ConfirmedLocalPlayerCount;
          end;
          if SelectedPlayerCount > 0 then Ini.Players := SelectedPlayerCount - 1;

          for I := 1 to SelectedPlayerCount do
          begin
            // TODO: is it really necessary for this screen to duplicate all these Ini. arrays?
            Ini.Name[I-1] := PlayerNames[I-1];
            Ini.PlayerColor[I-1] := Num[I-1];
            Ini.SingColor[I-1] := Num[I-1];
            Ini.PlayerLevel[I-1] := PlayerLevel[I-1];

            Ini.PlayerAvatar[I-1] := AvatarsMD5[PlayerAvatars[I-1]];
          end;

          LoadPlayersFromIni;

          for I := SelectedPlayerCount - 1 downto 0 do
            Ini.RememberUsedNames([PlayerNames[I]]);
          Ini.SaveNumberOfPlayers;
          Ini.SaveNames;
          Ini.SavePlayerColors;
          Ini.SavePlayerAvatars;
          Ini.SavePlayerLevels;

          LoadPlayersColors;
          Theme.ThemeScoreLoad;

          // Reload ScreenSing and ScreenScore because of player colors
          // TODO: do this better  REALLY NECESSARY?
          ScreenScore.Free;
          ScreenSing.Free;

          ScreenScore := TScreenScore.Create;
          ScreenSing  := TScreenSingController.Create;
          //

          AudioPlayback.PlaySound(SoundLib.Start);

          if GoTo_SingScreen then
          begin
            // if we've been in the player screen, we need to show the warning again
            ScreenSing.CheckPlayerConfigOnNextSong := true;
            AudioPlayback.SetVolume(1.0);
            ScreenSong.StopMusicPreview();
            ScreenSong.StopVideoPreview();
            if ScreenContinuousPlayback.WaitingForPlayers then
              ScreenContinuousPlayback.PlayersReady
            else ScreenSong.StartSong;
            GoTo_SingScreen := false;
          end
          else
          begin
            FadeTo(@ScreenSong);
            GoTo_SingScreen := false;
          end;
        end;

      // Up and Down could be done at the same time,
      // but I don't want to declare variables inside
      // functions like this one, called so many times
      SDLK_DOWN:
      begin
        InteractNext;
        SetTextInput(Button[PlayerName].Selected);
      end;

      SDLK_UP:
      begin
        InteractPrev;
        SetTextInput(Button[PlayerName].Selected);
      end;

      SDLK_RIGHT:
        begin
          AudioPlayback.PlaySound(SoundLib.Change);
          if Interaction = PlayerMicIID then ChangeMic(1);

          if (Interaction in [PlayersCountIID, PlayerColorIID, PlayerSelectLevelIID, PlayerSelectVoiceIID]) then
            InteractInc;

          if (Interaction = PlayersCountIID) then
            RefreshPlayers();

          if (Interaction = PlayerSelectIID) then
          begin //TODO: adapt this to new playersize
              if (PlayerIndex < SelectedPlayerCount-1) then
            begin
              PlayerIndex := PlayerIndex + 1;

              RefreshProfile();

              isScrolling := true;
              AvatarTarget := PlayerAvatars[PlayerIndex];
            end;
          end;

          if (Interaction = PlayerAvatarIID) then
          begin
            SelectNext;
            SetAvatarScroll;
            PlayerAvatars[PlayerIndex] := AvatarTarget;
            SetPlayerAvatar(PlayerIndex);
          end;

          if (Interaction = PlayerColorIID) then
          begin
            RefreshColor();
            SelectsS[PlayerColor].SetSelect(true);
          end;

          if Interaction = PlayerSelectVoiceIID then
            VoiceAssignments.SetVoice(PlayerIndex, VoiceIndex, CatSongs.Song[CatSongs.Selected].VoiceCount);

          if (Interaction = PlayerSelectLevelIID) then
          begin
            PlayerLevel[PlayerIndex] := LevelIndex;
          end;

        end;
      SDLK_LEFT:
        begin
          AudioPlayback.PlaySound(SoundLib.Change);
          if Interaction = PlayerMicIID then ChangeMic(-1);

          if (Interaction in [PlayersCountIID, PlayerColorIID, PlayerSelectLevelIID, PlayerSelectVoiceIID]) then
            InteractDec;

          if (Interaction = PlayersCountIID) then
            RefreshPlayers();

          if (Interaction = PlayerSelectIID) then
          begin
            if (PlayerIndex > 0) then
            begin
              PlayerIndex := PlayerIndex - 1;

              RefreshProfile();

              isScrolling := true;
              AvatarTarget := PlayerAvatars[PlayerIndex];
            end;
          end;

          if (Interaction = PlayerAvatarIID) then
          begin
            SelectPrev;
            SetAvatarScroll;
            PlayerAvatars[PlayerIndex] := AvatarTarget;
            SetPlayerAvatar(PlayerIndex);
          end;

          if (Interaction = PlayerColorIID) then
          begin
            RefreshColor();
            SelectsS[PlayerColor].SetSelect(true);
          end;

          if Interaction = PlayerSelectVoiceIID then
            VoiceAssignments.SetVoice(PlayerIndex, VoiceIndex, CatSongs.Song[CatSongs.Selected].VoiceCount);

          if (Interaction = PlayerSelectLevelIID) then
          begin
            PlayerLevel[PlayerIndex] := LevelIndex;
          end;

        end;

    end;
  end;
end;

procedure TScreenName.GenerateAvatars();
var
  I: integer;
  Avatar: TAvatar;
  AvatarFile: IPath;
  Hash: string;
  NoAvatarFile: IPath;
begin

  SetLength(PlayerAvatarButton, Length(AvatarsList) + 1);

  // 1st no-avatar dummy
  for I := 1 to UIni.IMaxPlayerCount do
  begin
    NoAvatarFile := Skin.GetTextureFileName('NoAvatar_P' + IntToStr(I));
    if not NoAvatarFile.IsFile then
      NoAvatarFile := Skin.GetTextureFileName('NoAvatar_P1');
    if not NoAvatarFile.IsFile then
      NoAvatarFile := Skin.GetTextureFileName('NoAvatar');

    NoAvatarTexture[I] := Renderer.GetTexture(NoAvatarFile, TEXTURE_TYPE_TRANSPARENT, $FFFFFF);
    NoAvatarTexture[I].ScaleMode := lsUniform;
  end;

  // create no-avatar
  PlayerAvatarButton[0] := AddButton(Theme.Name.PlayerAvatar);
  Button[PlayerAvatarButton[0]].Texture.Free;
  Button[PlayerAvatarButton[0]].Texture := NoAvatarTexture[1].Clone;
  Button[PlayerAvatarButton[0]].Selectable := false;
  Button[PlayerAvatarButton[0]].Selected := false;
  Button[PlayerAvatarButton[0]].Visible := false;

  // create avatars buttons
  for I := 1 to High(AvatarsList) do
  begin
    // create avatar
    PlayerAvatarButton[I] := AddButton(Theme.Name.PlayerAvatar);

    // load avatar directly from its file
    Avatar := Avatars.AddAvatar(AvatarsList[I]);

    if (Avatar <> nil) then
    begin
      Button[PlayerAvatarButton[I]].Texture.Free;
      Button[PlayerAvatarButton[I]].Texture := Avatar.GetTexture();
      Button[PlayerAvatarButton[I]].Selectable := false;
      Button[PlayerAvatarButton[I]].Selected := false;
      Button[PlayerAvatarButton[I]].Visible := false;
    end;

    Avatar.Free;
  end;

end;

procedure TScreenName.ChangeSelectPlayerPosition(Player: integer);
var
  BaseBounds: TPlayerSlotRect;
  Count: integer;
  FittedRect: TPlayerSlotRect;
  SelectButton: integer;
begin
  Count := SelectedPlayerCount;
  BaseBounds := GetNamePlayerSelectBaseBounds;
  FittedRect := GetNamePlayerSelectFittedRect(Player, Count);

  Button[PlayerSelect].X := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateFrame.X + Theme.Name.PlayerSelectCurrent.X,
    BaseBounds.X, BaseBounds.W, FittedRect.X, FittedRect.W);
  Button[PlayerSelect].Y := ScaleNameCoord(
    Theme.Name.PlayerSelectCurrent.Y, BaseBounds.Y, BaseBounds.H, FittedRect.Y, FittedRect.H);
  Button[PlayerSelect].W := ScaleNameLength(
    Theme.Name.PlayerSelectCurrent.W, BaseBounds.W, FittedRect.W);
  Button[PlayerSelect].H := ScaleNameLength(
    Theme.Name.PlayerSelectCurrent.H, BaseBounds.H, FittedRect.H);
  Button[PlayerSelect].SelectW := Button[PlayerSelect].W;
  Button[PlayerSelect].SelectH := Button[PlayerSelect].H;

  SelectButton := Interactions[PlayerSelectIID].Num;
  Button[SelectButton].X := Button[PlayerSelect].X;
  Button[SelectButton].Y := Button[PlayerSelect].Y;
  Button[SelectButton].W := Button[PlayerSelect].W;
  Button[SelectButton].H := Button[PlayerSelect].H;
  Button[SelectButton].SelectW := Button[PlayerSelect].SelectW;
  Button[SelectButton].SelectH := Button[PlayerSelect].SelectH;
end;

procedure TScreenName.ApplyPlayerSelectLayout(Player, PlayerCount: integer);
var
  BaseBounds: TPlayerSlotRect;
  FittedRect: TPlayerSlotRect;
begin
  BaseBounds := GetNamePlayerSelectBaseBounds;
  FittedRect := GetNamePlayerSelectFittedRect(Player, PlayerCount);

  Statics[PlayerCurrent[Player]].Texture.X := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateFrame.X, BaseBounds.X, BaseBounds.W, FittedRect.X, FittedRect.W);
  Statics[PlayerCurrent[Player]].Texture.Y := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateFrame.Y, BaseBounds.Y, BaseBounds.H, FittedRect.Y, FittedRect.H);
  Statics[PlayerCurrent[Player]].Texture.W := ScaleNameLength(
    Theme.Name.PlayerSelectTemplateFrame.W, BaseBounds.W, FittedRect.W);
  Statics[PlayerCurrent[Player]].Texture.H := ScaleNameLength(
    Theme.Name.PlayerSelectTemplateFrame.H, BaseBounds.H, FittedRect.H);

  Text[PlayerCurrentText[Player]].X := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateText.X, BaseBounds.X, BaseBounds.W, FittedRect.X, FittedRect.W);
  Text[PlayerCurrentText[Player]].Y := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateText.Y, BaseBounds.Y, BaseBounds.H, FittedRect.Y, FittedRect.H) -
    Max(2, ScaleNameLength(4, BaseBounds.H, FittedRect.H));
  Text[PlayerCurrentText[Player]].Size := Max(8, ScaleNameLength(
    Theme.Name.PlayerSelectTemplateText.Size, BaseBounds.H, FittedRect.H));

  Statics[PlayerCurrentAvatar[Player]].Texture.X := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateAvatar.X, BaseBounds.X, BaseBounds.W, FittedRect.X, FittedRect.W);
  Statics[PlayerCurrentAvatar[Player]].Texture.Y := ScaleNameCoord(
    Theme.Name.PlayerSelectTemplateAvatar.Y, BaseBounds.Y, BaseBounds.H, FittedRect.Y, FittedRect.H);
  Statics[PlayerCurrentAvatar[Player]].Texture.W := ScaleNameLength(
    Theme.Name.PlayerSelectTemplateAvatar.W, BaseBounds.W, FittedRect.W);
  Statics[PlayerCurrentAvatar[Player]].Texture.H := ScaleNameLength(
    Theme.Name.PlayerSelectTemplateAvatar.H, BaseBounds.H, FittedRect.H);
  with Statics[PlayerCurrentAvatar[Player]].Texture do
  begin
    FitLayoutChild(X, Y, W, H,
      Statics[PlayerCurrent[Player]].Texture.X, Statics[PlayerCurrent[Player]].Texture.Y,
      Statics[PlayerCurrent[Player]].Texture.W, Statics[PlayerCurrent[Player]].Texture.H,
      Statics[PlayerCurrent[Player]].Texture.ScaleMode, 0.5);
    ScaleMode := lsStretch;
  end;
end;

function TScreenName.HighestRemoteSlot: integer;
begin
  for Result := UIni.IMaxPlayerCount downto 1 do
    if RemoteInputProcessor.HasAssignedPlayer(Result - 1) then Exit;
  Result := 0;
end;

function TScreenName.SelectedPlayerCount: integer;
begin
  if Party.bPartyGame then Exit(UIni.IPlayersVals[CountIndex]);
  if CountIndex = LyricsOnlyIndex then Exit(0);
  Result := Max(SelectedLocalPlayerCount, HighestRemoteSlot);
end;

function TScreenName.SelectedLocalPlayerCount: integer;
begin
  Result := Max(0, CountIndex - PhonesOnlyIndex);
end;

function TScreenName.LocalPlayerCount: integer;
begin
  if ConfirmedLocalPlayerCount < 0 then Exit(UIni.IPlayersVals[Ini.Players]);
  Result := ConfirmedLocalPlayerCount;
end;

function TScreenName.ActivePlayerCount: integer;
var Slots: cardinal;
begin
  if Party.bPartyGame then Exit(UIni.IPlayersVals[Ini.Players]);
  if LyricsOnly then Exit(0);
  if ConfirmedLocalPlayerCount < 0 then
    Exit(AudioInputProcessor.ConfiguredPlayerCount(LocalPlayerCount, Slots));
  Result := Max(ConfirmedLocalPlayerCount, HighestRemoteSlot);
end;

procedure TScreenName.UpdateAssignedPlayers(Force: boolean);
var
  Slots: cardinal;
  Channels, I, Limit: integer;
  Options: array of UTF8String;
begin
  if Party.bPartyGame then Exit;
  Slots := 0;
  for I := 0 to UIni.IMaxPlayerCount - 1 do
    if RemoteInputProcessor.HasAssignedPlayer(I) then
      Slots := Slots or (cardinal(1) shl I);
  Channels := 0;
  for I := 0 to High(AudioInputProcessor.DeviceList) do
    if Assigned(AudioInputProcessor.DeviceList[I]) then
      Inc(Channels, AudioInputProcessor.DeviceList[I].AudioFormat.Channels);
  if not Force and (Slots = RemoteSlots) and (Channels = AvailableChannels) then Exit;
  RemoteSlots := Slots;
  AvailableChannels := Channels;
  Limit := 0;
  for I := 0 to UIni.IMaxPlayerCount - 1 do
  begin
    if (Slots and (cardinal(1) shl I)) = 0 then
    begin
      if Channels = 0 then Break;
      Dec(Channels);
    end;
    Inc(Limit);
  end;
  Limit := Max(1, Limit);
  CountIndex := Min(CountIndex, PhonesOnlyIndex + Limit);
  SetLength(Options, PhonesOnlyIndex + Limit + 1);
  Options[LyricsOnlyIndex] := Language.Translate('CONTINUOUS_ZERO_PLAYERS');
  Options[PhonesOnlyIndex] := Language.Translate('SING_SETUP_PHONES_ONLY');
  for I := 1 to Limit do Options[PhonesOnlyIndex + I] := IntToStr(I);
  UpdateSelectSlideOptions(PlayersCount, Options, CountIndex);
  if not Force then RefreshPlayers;
end;

function TScreenName.IsRosterGap(Index: integer): boolean;
begin
  Result := not Party.bPartyGame and (Index >= SelectedLocalPlayerCount) and
    not RemoteInputProcessor.HasAssignedPlayer(Index);
end;

function TScreenName.DisplayPlayerName(Index: integer): UTF8String;
begin
  if IsRosterGap(Index) then
    Result := Language.Translate('SING_OPTIONS_RECORD_NOONE')
  else
    Result := PlayerNames[Index];
end;

procedure TScreenName.RefreshPlayers();
var
  Count, I: integer;
  DesCol: TRGB;
begin

  UpdateAssignedPlayers(true);
  Count := SelectedPlayerCount;
  for I := 0 to High(Theme.Name.Text) do
    if Theme.Name.Text[I].Text = Language.Translate('SING_PLAYER_ENTER_NAME') then
      Text[I].Visible := Count > 0;
  for I := 0 to High(Theme.Name.Statics) do
    if SameText(Theme.Name.Statics[I].Tex, 'ButtonAZ') then
      Statics[I].Visible := Count > 0;

  while (PlayerIndex > Max(0, Count-1)) do
    PlayerIndex := PlayerIndex - 1;

  // Player Colors
  for I := 0 to Count-1 do
  begin
    ApplyPlayerSelectLayout(I, Count);

    if (Ini.PlayerColor[I] > 0) then
      Num[I] := NoRepeatColors(Ini.PlayerColor[I], I, 1)
    else
      Num[I] := NoRepeatColors(1, I, 1);

    DesCol := GetPlayerColor(Num[I]);

    Statics[PlayerCurrent[I]].Texture.ColR := DesCol.R;
    Statics[PlayerCurrent[I]].Texture.ColG := DesCol.G;
    Statics[PlayerCurrent[I]].Texture.ColB := DesCol.B;
  end;

  for I := 0 to UIni.IMaxPlayerCount-1 do
  begin
    Statics[PlayerCurrent[I]].Visible := I < Count;
    Text[PlayerCurrentText[I]].Visible := I < Count;
    Statics[PlayerCurrentAvatar[I]].Visible := I < Count;
  end;

  // list players
  for I := 0 to Count -1 do
  begin
    Text[PlayerCurrentText[I]].Text := DisplayPlayerName(I);
    SetPlayerAvatar(I);
  end;

  Button[PlayerName].Visible := false;
  Button[PlayerName].Selectable := false;
  Button[PlayerSelect].Visible := Count > 0;
  Button[PlayerSelect].Selectable := false;
  Button[PlayerAvatar].Visible := Count > 0;
  Button[PlayerAvatar].Selectable := Count > 0;
  Button[Interactions[PlayerSelectIID].Num].Visible := Count > 0;
  Button[Interactions[PlayerSelectIID].Num].Selectable := Count > 0;
  SelectsS[PlayerColor].Visible := Count > 0;
  SelectsS[PlayerSelectLevel].Visible := Count > 0;
  if Count = 0 then SelectsS[PlayerMic].Visible := false;
  RefreshVoice;
  for I := 0 to High(PlayerAvatarButton) do Button[PlayerAvatarButton[I]].Visible := false;
  RefreshProfile();
  if not IsSelectable(Interaction) then
  begin
    Interaction := PlayersCountIID;
    StopTextInput;
  end;
  if Count = 0 then Exit;

  AvatarTarget := PlayerAvatars[PlayerIndex];
  AvatarCurrent := AvatarTarget;

end;

procedure TScreenName.RefreshVoice;
var
  Options: array of UTF8String;
  I: integer;
begin
  SelectsS[PlayerSelectVoice].Visible := (SelectedPlayerCount > 0) and Goto_SingScreen and
    (CatSongs.Selected >= 0) and (CatSongs.Selected < Length(CatSongs.Song)) and
    CatSongs.Song[CatSongs.Selected].isDuet;
  if not SelectsS[PlayerSelectVoice].Visible then Exit;
  VoiceAssignments.SelectSong(CatSongs.Song[CatSongs.Selected]);
  SetLength(Options, CatSongs.Song[CatSongs.Selected].VoiceCount);
  for I := 0 to High(Options) do
    Options[I] := Format(Language.Translate('SING_VOICE_NUMBER'), [I + 1]) +
      ': ' + CatSongs.Song[CatSongs.Selected].DuetNames[I];
  VoiceIndex := VoiceAssignments.VoiceForPlayer(PlayerIndex, Length(Options));
  UpdateSelectSlideOptions(PlayerSelectVoice, Options, VoiceIndex);
  SelectsS[PlayerSelectVoice].SetSelectOpt(VoiceIndex);
end;

procedure TScreenName.RefreshProfile();
var
  ITmp: array of UTF8String;
  Count, Max, I, J, Index: integer;
  Used: boolean;
begin
  if SelectedPlayerCount = 0 then Exit;
  Button[PlayerName].Visible := not IsRosterGap(PlayerIndex);
  Button[PlayerName].Selectable := Button[PlayerName].Visible;
  // no-avatar for current player
  Button[PlayerAvatarButton[0]].Texture.Free;
  Button[PlayerAvatarButton[0]].Texture := NoAvatarTexture[PlayerIndex + 1].Clone();

  Button[PlayerName].Text[0].Text := PlayerNames[PlayerIndex];

  SelectsS[PlayerSelectLevel].SetSelectOpt(PlayerLevel[PlayerIndex]);
  RefreshMicSelector;
  RefreshVoice;

  Count := SelectedPlayerCount;

  ChangeSelectPlayerPosition(PlayerIndex);

  PlayerColorButton(Num[PlayerIndex]);

  Max := Length(IPlayerColorTranslated) - Count + 1;
  SetLength(ITmp, Max);

  APlayerColor := nil;
  SetLength(APlayerColor, Max);

  Index := 0;
  for I := 0 to High(IPlayerColorTranslated) do      //for every color
  begin
    Used := false;

    for J := 0 to Count -1 do      //for every active player
    begin
      if (Num[J] - 1 = I) and (J <> PlayerIndex) then   //check if color is already used for not current player
      begin
        Used := true;
        break;
      end;
    end;

    if not (Used) then
    begin
      ITmp[Index] := IPlayerColorTranslated[I];
      APlayerColor[Index] := I + 1;
      Index := Index + 1;
    end;
  end;

  UpdateSelectSlideOptions(PlayerColor, ITmp, ColorIndex);

  for I := 0 to High(APlayerColor) do
  begin
    if (Num[PlayerIndex] = APlayerColor[I]) then
    begin
      SelectsS[PlayerColor].SetSelectOpt(I);
      break;
    end;
  end;

end;

procedure TScreenName.RefreshColor();
begin

  PlayerColorButton(APlayerColor[ColorIndex]);

end;

function TScreenName.NoRepeatColors(ColorP:integer; Interaction:integer; Pos:integer):integer;
var
  Z, Count:integer;
begin
  Count := SelectedPlayerCount;

  if (ColorP > Length(IPlayerColorTranslated)) then
    ColorP := NoRepeatColors(1, Interaction, Pos);

  if (ColorP <= 0) then
    ColorP := NoRepeatColors(High(IPlayerColorTranslated), Interaction, Pos);

  for Z := Count -1 downto 0 do
  begin
    if (Num[Z] = ColorP) and (Z <> Interaction) then
      ColorP := NoRepeatColors(ColorP + Pos, Interaction, Pos)
  end;

  Result := ColorP;

end;

procedure TScreenName.PlayerColorButton(K: integer);
var
  Col, DesCol: TRGB;
begin
  if SelectedPlayerCount = 0 then Exit;

  Col := GetPlayerLightColor(K);

  if Theme.Name.TintControls then
  begin
    Button[PlayerName].SelectColR:= Col.R;
    Button[PlayerName].SelectColG:= Col.G;
    Button[PlayerName].SelectColB:= Col.B;

    Button[PlayerAvatar].SelectColR:= Col.R;
    Button[PlayerAvatar].SelectColG:= Col.G;
    Button[PlayerAvatar].SelectColB:= Col.B;

    SelectsS[PlayerColor].SBGColR:= Col.R;
    SelectsS[PlayerColor].SBGColG:= Col.G;
    SelectsS[PlayerColor].SBGColB:= Col.B;

    SelectsS[PlayerSelectLevel].SBGColR:= Col.R;
    SelectsS[PlayerSelectLevel].SBGColG:= Col.G;
    SelectsS[PlayerSelectLevel].SBGColB:= Col.B;
    SelectsS[PlayerSelectVoice].SBGColR := Col.R;
    SelectsS[PlayerSelectVoice].SBGColG := Col.G;
    SelectsS[PlayerSelectVoice].SBGColB := Col.B;
    SelectsS[PlayerMic].SBGColR := Col.R;
    SelectsS[PlayerMic].SBGColG := Col.G;
    SelectsS[PlayerMic].SBGColB := Col.B;

  end;
  DesCol := GetPlayerColor(K);

  Statics[PlayerCurrent[PlayerIndex]].Texture.ColR := DesCol.R;
  Statics[PlayerCurrent[PlayerIndex]].Texture.ColG := DesCol.G;
  Statics[PlayerCurrent[PlayerIndex]].Texture.ColB := DesCol.B;

  if Theme.Name.TintControls then
  begin
    Button[PlayerName].DeselectColR:= DesCol.R;
    Button[PlayerName].DeselectColG:= DesCol.G;
    Button[PlayerName].DeselectColB:= DesCol.B;

    Button[PlayerAvatar].DeselectColR:= DesCol.R;
    Button[PlayerAvatar].DeselectColG:= DesCol.G;
    Button[PlayerAvatar].DeselectColB:= DesCol.B;

    SelectsS[PlayerColor].SBGDColR := DesCol.R;
    SelectsS[PlayerColor].SBGDColG:= DesCol.G;
    SelectsS[PlayerColor].SBGDColB:= DesCol.B;

    SelectsS[PlayerSelectLevel].SBGDColR := DesCol.R;
    SelectsS[PlayerSelectLevel].SBGDColG:= DesCol.G;
    SelectsS[PlayerSelectLevel].SBGDColB:= DesCol.B;
    SelectsS[PlayerSelectVoice].SBGDColR := DesCol.R;
    SelectsS[PlayerSelectVoice].SBGDColG := DesCol.G;
    SelectsS[PlayerSelectVoice].SBGDColB := DesCol.B;
    SelectsS[PlayerMic].SBGDColR := DesCol.R;
    SelectsS[PlayerMic].SBGDColG := DesCol.G;
    SelectsS[PlayerMic].SBGDColB := DesCol.B;

  end;
  if Skin.ColorizeDefaultAvatars then
  begin
    Button[PlayerAvatarButton[0]].Texture.ColR := DesCol.R;
    Button[PlayerAvatarButton[0]].Texture.ColG := DesCol.G;
    Button[PlayerAvatarButton[0]].Texture.ColB := DesCol.B;
  end;

  if (PlayerAvatars[PlayerIndex] = 0) and Skin.ColorizeDefaultAvatars then
  begin
    Statics[PlayerCurrentAvatar[PlayerIndex]].Texture.ColR := DesCol.R;
    Statics[PlayerCurrentAvatar[PlayerIndex]].Texture.ColG := DesCol.G;
    Statics[PlayerCurrentAvatar[PlayerIndex]].Texture.ColB := DesCol.B;
  end;

  SelectsS[PlayerColor].SetSelect(false);
  SelectsS[PlayerSelectLevel].SetSelect(false);
  SelectsS[PlayerSelectVoice].SetSelect(false);
  Button[PlayerName].SetSelect(false);
  Button[PlayerAvatar].SetSelect(false);

  Num[PlayerIndex] := K;
  Ini.PlayerColor[PlayerIndex] := K;
end;

constructor TScreenName.Create;
var
  I: integer;
  WhitePixel: cardinal;
begin
  inherited Create;
  LoadFromTheme(Theme.Name);

  Theme.Name.SelectPlayersCount.oneItemOnly := true;
  Theme.Name.SelectPlayersCount.showArrows := true;
  CardPanel := -1;
  CardFocus := -1;
  if Theme.Name.Cards.Enabled then
  begin
    CardPanel := AddStatic(Theme.Name.Cards.Panel);
    CardFocus := AddStatic(Theme.Name.Cards.Focus);
    Statics[CardPanel].Visible := false;
    Statics[CardFocus].Visible := false;
    MicFrame := AddStatic(Theme.Name.Cards.Focus);
    Statics[MicFrame].Texture.Free;
    WhitePixel := $FFFFFFFF;
    Statics[MicFrame].Texture := Renderer.CreateTexture(PChar(@WhitePixel),
      PATH_NONE, 1, 1, TEXTURE_TYPE_TRANSPARENT, false);
    Statics[MicFrame].Visible := false;
  end;
  PlayersCount := AddSelectSlide(Theme.Name.SelectPlayersCount, CountIndex, IPlayers);
  PlayersCountIID := High(Interactions);

  for I := 0 to UIni.IMaxPlayerCount -1 do
  begin
    PlayerCurrentAvatar[I] := AddStaticRectangle(Theme.Name.PlayerSelectAvatar[I]);
    Statics[PlayerCurrentAvatar[I]].Texture.Z := Theme.Name.PlayerSelectAvatar[I].Z;
    PlayerCurrent[I] := AddStatic(Theme.Name.PlayerSelect[I]);
    PlayerCurrentText[I] := AddText(Theme.Name.PlayerSelectText[I]);
  end;

  PlayerSelect := AddButton(Theme.Name.PlayerSelectCurrent);
  Button[PlayerSelect].Selectable := false;

  AddButton(0, 0, 0, 0, Skin.GetTextureFileName(Theme.Name.PlayerSelectCurrent.Tex), Theme.Name.PlayerSelectCurrent.Typ, false);
  PlayerSelectIID := High(Interactions);
  Button[Interactions[PlayerSelectIID].Num].SelectInt := 0;
  Button[Interactions[PlayerSelectIID].Num].DeselectInt := 0;
  Button[Interactions[PlayerSelectIID].Num].Texture.Alpha := 0;
  Button[Interactions[PlayerSelectIID].Num].DeSelectTexture.Alpha := 0;

  PlayerAvatar := AddButton(Theme.Name.PlayerButtonAvatar);
  PlayerAvatarIID := High(Interactions);

  PlayerName := AddButton(Theme.Name.PlayerButtonName);
  PlayerNameIID := High(Interactions);
  Button[PlayerName].Text[0].Writable := true;
  Button[PlayerName].Text[0].NameEntryField := true;

  Theme.Name.SelectPlayerColor.oneItemOnly := true;
  Theme.Name.SelectPlayerColor.showArrows := true;
  PlayerColor := AddSelectSlide(Theme.Name.SelectPlayerColor, ColorIndex, IPlayerColorTranslated);
  PlayerColorIID := High(Interactions);

  Theme.Name.SelectPlayerLevel.oneItemOnly := true;
  Theme.Name.SelectPlayerLevel.showArrows := true;
  PlayerSelectLevel := AddSelectSlide(Theme.Name.SelectPlayerLevel, LevelIndex, IDifficultyTranslated);
  PlayerSelectLevelIID := High(Interactions);

  Theme.Name.SelectPlayerVoice.oneItemOnly := true;
  Theme.Name.SelectPlayerVoice.showArrows := true;
  PlayerSelectVoice := AddSelectSlide(Theme.Name.SelectPlayerVoice, VoiceIndex, ['']);
  PlayerSelectVoiceIID := High(Interactions);

  Theme.Name.SelectPlayerMic.showArrows := true;
  Theme.Name.SelectPlayerMic.oneItemOnly := true;
  PlayerMic := AddSelectSlide(Theme.Name.SelectPlayerMic, MicOption, ['']);
  PlayerMicIID := High(Interactions);
  SelectsS[PlayerMic].Visible := false;
  MicPickerPlayer := -1;
  ConfirmedLocalPlayerCount := Ini.SetupLocalPlayers;
  SelectsS[PlayerSelectVoice].Visible := false;

  isScrolling := false;

  GenerateAvatars();

  DelayHintText := AddKeyHint(Theme.Name.DelayHint);
  Text[DelayHintText].Visible := false;
  DelayApplyButton := AddDelayButton(Theme.Name.DelayApplyButton, 'SLOT_DELAY_APPLY');
  DelayCancelButton := AddDelayButton(Theme.Name.DelayCancelButton, 'SLOT_DELAY_CANCEL');

  NumVisibleAvatars := Theme.Name.PlayerScrollAvatar.NumAvatars;
  DistanceVisibleAvatars := Theme.Name.PlayerScrollAvatar.DistanceAvatars;

  Interaction := 0;
end;

procedure TScreenName.SetPlayerAvatar(Player: integer);
var
  Col: TRGB;
  X: real;
  Y: real;
  W: real;
  H: real;
  Z: real;
begin
  X := Statics[PlayerCurrentAvatar[Player]].Texture.X;
  Y := Statics[PlayerCurrentAvatar[Player]].Texture.Y;
  W := Statics[PlayerCurrentAvatar[Player]].Texture.W;
  H := Statics[PlayerCurrentAvatar[Player]].Texture.H;
  Z := Statics[PlayerCurrentAvatar[Player]].Texture.Z;

  if (PlayerAvatars[Player] = 0) then
  begin
    Statics[PlayerCurrentAvatar[Player]].Texture.Free;
    Statics[PlayerCurrentAvatar[Player]].Texture := NoAvatarTexture[Player + 1].Clone;

    Col := GetPlayerColor(Num[Player]);

    if Skin.ColorizeDefaultAvatars then
    begin
      Statics[PlayerCurrentAvatar[Player]].Texture.ColR := Col.R;
      Statics[PlayerCurrentAvatar[Player]].Texture.ColG := Col.G;
      Statics[PlayerCurrentAvatar[Player]].Texture.ColB := Col.B;
    end;
  end
  else
  begin
    Statics[PlayerCurrentAvatar[Player]].Texture.Free;
    Statics[PlayerCurrentAvatar[Player]].Texture := Button[PlayerAvatarButton[PlayerAvatars[Player]]].Texture.Clone;
  end;

  Statics[PlayerCurrentAvatar[Player]].Texture.X := X;
  Statics[PlayerCurrentAvatar[Player]].Texture.Y := Y;
  Statics[PlayerCurrentAvatar[Player]].Texture.W := W;
  Statics[PlayerCurrentAvatar[Player]].Texture.H := H;
  Statics[PlayerCurrentAvatar[Player]].Texture.Z := Z;
  Statics[PlayerCurrentAvatar[Player]].Texture.Int := 1;
  Statics[PlayerCurrentAvatar[Player]].Texture.CornerRadius := Theme.Name.PlayerSelectAvatar[Player].CornerRadius;
  Statics[PlayerCurrentAvatar[Player]].Texture.ScaleMode := lsStretch;

end;

// sets up Player and the avatar textures from the player settings in Ini
procedure TScreenName.LoadPlayersFromIni(LoadAvatars: boolean);
var
  I:           integer;
  AvatarIndex: integer;
  Col:         TRGB;
begin
  PlayersPlay := ActivePlayerCount;
  SetLength(Player, PlayersPlay);

  for I := 0 to PlayersPlay - 1 do
  begin
    PlayerNames[I] := Ini.Name[I];
    PlayerLevel[I] := Ini.PlayerLevel[I];
    PlayerAvatars[I] := Max(0, GetArrayIndex(AvatarsMD5, Ini.PlayerAvatar[I]));
    if not Party.bPartyGame and (PlayerInputSource(I) = pisNone) then
      Player[I].Name := Language.Translate('SING_OPTIONS_RECORD_NOONE')
    else
      Player[I].Name := Ini.Name[I];
    Player[I].Level := Ini.PlayerLevel[I];

    if not LoadAvatars then
      Continue;

    if Assigned(AvatarPlayerTextures[I+1]) and
      (AvatarPlayerTextures[I+1] <> NoAvatarTexture[I+1]) then
      FreeAndNil(AvatarPlayerTextures[I+1]);
    AvatarIndex := GetArrayIndex(AvatarsMD5, Ini.PlayerAvatar[I]);
    if (AvatarIndex > 0) then
    begin
      Button[PlayerAvatarButton[AvatarIndex]].Texture.Int := 1;
      AvatarPlayerTextures[I+1] := Button[PlayerAvatarButton[AvatarIndex]].Texture.Clone();
    end
    else
    begin
      AvatarPlayerTextures[I+1] := NoAvatarTexture[I+1];

      Col := GetPlayerColor(Ini.PlayerColor[I]);

      if Skin.ColorizeDefaultAvatars then
      begin
        AvatarPlayerTextures[I+1].ColR := Col.R;
        AvatarPlayerTextures[I+1].ColG := Col.G;
        AvatarPlayerTextures[I+1].ColB := Col.B;
      end;
    end;
  end;
  if Display.CurrentScreen = @ScreenName then
  begin
    RefreshPlayers;
    RefreshProfile;
  end;
end;

procedure TScreenName.OnHide;
begin
  CloseDelayMeasurement;
  StopTextInput;
  if OwnsMicPreview then AudioInput.CaptureStop(true);
  OwnsMicPreview := false;
  MicDevicesScanned := false;
  MicPickerPlayer := -1;
  FillChar(MicActivity, SizeOf(MicActivity), 0);
  FillChar(MicClippedUntil, SizeOf(MicClippedUntil), 0);
  inherited;
end;

destructor TScreenName.Destroy;
begin
  DelayMeasurement.Free;
  inherited;
end;

function TScreenName.DelayMeasurementOpen: boolean;
begin
  Result := Assigned(DelayMeasurement);
end;

function TScreenName.DelaySlots: cardinal;
var LocalCount: integer;
begin
  Result := 0;
  if SelectedPlayerCount = 0 then Exit;
  LocalCount := SelectedLocalPlayerCount;
  if Party.bPartyGame then LocalCount := SelectedPlayerCount;
  AudioInputProcessor.ConfiguredPlayerCount(LocalCount, Result);
end;

procedure TScreenName.StartDelayMeasurement;
var Slots: cardinal;
begin
  Slots := DelaySlots;
  if Slots = 0 then
  begin
    ScreenPopupError.ShowPopup(Language.Translate('SLOT_DELAY_NO_INPUTS'));
    Exit;
  end;
  if SelectedPlayerCount = 0 then Exit;
  if Ini.SfxVolume = 0 then
  begin
    ScreenPopupError.ShowPopup(Language.Translate('SLOT_DELAY_MUTED'));
    Exit;
  end;
  if Ini.MaxFramerateGet < 30 then
  begin
    ScreenPopupError.ShowPopup(Language.Translate('SLOT_DELAY_LOW_FPS'));
    Exit;
  end;
  ScreenSong.StopMusicPreview;
  DelayPausedBgMusic := Assigned(SoundLib) and Assigned(SoundLib.BGMusic) and
    (SoundLib.BGMusic.Status = ssPlaying);
  if DelayPausedBgMusic then SoundLib.PauseBgMusic;
  DelayMeasurement := TSlotDelayMeasurement.Create;
  UpdateMicActivity;
  if not DelayMeasurement.Start(Slots) then
  begin
    CloseDelayMeasurement;
    ScreenPopupError.ShowPopup(Language.Translate('SLOT_DELAY_OUTPUT_ERROR'));
  end;
end;

procedure TScreenName.CloseDelayMeasurement;
begin
  FreeAndNil(DelayMeasurement);
  if DelayPausedBgMusic and Assigned(SoundLib) and Assigned(SoundLib.BGMusic) and
    (SoundLib.BGMusic.Status = ssPaused) then
    SoundLib.BGMusic.Play;
  DelayPausedBgMusic := false;
end;

procedure TScreenName.ApplyDelayMeasurement;
begin
  if DelayMeasurement.Measuring or not DelayMeasurement.HasResult then Exit;
  DelayMeasurement.Apply(DelaySlots);
  CloseDelayMeasurement;
end;

function TScreenName.AddDelayButton(const Style: TThemeButton; const Key: UTF8String): integer;
var
  Appearance: TThemeButton;
  CaptionStyle: TThemeText;
begin
  Appearance := Style;
  if Length(Appearance.Text) > 0 then CaptionStyle := Appearance.Text[0]
  else CaptionStyle := Theme.Name.DelayText;
  Appearance.Text := nil;
  SetLength(Appearance.Text, 1);
  CaptionStyle.Text := Language.Translate(Key);
  CaptionStyle.Align := 1;
  CaptionStyle.Size := Min(CaptionStyle.Size, Max(12, Appearance.H - 10));
  CaptionStyle.X := Appearance.W div 2;
  CaptionStyle.Y := (Appearance.H - CaptionStyle.Size) div 2;
  Appearance.Text[0] := CaptionStyle;
  Appearance.Parent := 0;
  Appearance.Fade := false;
  Appearance.Reflection := false;
  Appearance.ScaleMode := lsStretch;
  Result := AddButton(Appearance);
  // These actions are navigated by the modal shortcuts and handled by ParseMouse.
  SetLength(Interactions, Length(Interactions) - 1);
  Button[Result].Visible := false;
end;

procedure TScreenName.DrawDelayButton(Index: integer);
begin
  Button[Index].Visible := true;
  Button[Index].Draw;
  Button[Index].Visible := false;
end;

procedure TScreenName.DrawDelayMeasurement;
var Slot, Row, Count, RowsPerColumn: integer;
    X: real;
    Fit: TAudioCalibrationResult;
    Caption: UTF8String;
  procedure LabelAt(const Value: UTF8String; X, Y: real; Size: integer; WidthFraction: real = 0.9);
  var Width: real;
  begin
    SetFontFamily(ResolveThemeFont(Theme.Name.DelayText.FontFile, Theme.Name.DelayText.Font));
    SetFontSize(Size);
    SetFontStyle(Theme.Name.DelayText.Style);
    SetFontItalic(false);
    SetFontReflection(false, 0);
    with Theme.Name.DelayText do SetFontColor(ColR, ColG, ColB, 1);
    Width := TextWidth(Value);
    if Width > RenderW * WidthFraction then
      SetFontSize(Size * RenderW * WidthFraction / Width);
    SetFontPos(X - TextWidth(Value) / 2, Y);
    PrintText(Value);
  end;
begin
  if not Assigned(DelayMeasurement) then Exit;
  Renderer.DrawQuad(0, 0, 0, RenderW, RenderH, 0, 0, 0, 0.82);
  with Theme.Name.DelayText do
    LabelAt(Language.Translate('SLOT_DELAY_TITLE'), X, Y, Size);
  if DelayMeasurement.Measuring then
    LabelAt(Language.Translate('SLOT_DELAY_LISTENING'), RenderW / 2, 103, 18)
  else
  begin
    Count := 0;
    for Slot := 0 to UIni.IMaxPlayerCount - 1 do
      if (DelayMeasurement.Slots and (cardinal(1) shl Slot)) <> 0 then Inc(Count);
    RowsPerColumn := Min(UIni.IMaxPlayerCount div 2, Max(1, Count));
    Row := 0;
    for Slot := 0 to UIni.IMaxPlayerCount - 1 do
      if (DelayMeasurement.Slots and (cardinal(1) shl Slot)) <> 0 then
      begin
        Fit := DelayMeasurement.ResultFor(Slot);
        if Fit.HasEstimate then
          Caption := Format(Language.Translate('SLOT_DELAY_RESULT'), [Slot + 1, Fit.DelayMs, Fit.UncertaintyMs])
        else
          Caption := Format(Language.Translate('SLOT_DELAY_NO_RESULT'), [Slot + 1]);
        X := RenderW / 2;
        if Count > RowsPerColumn then
        begin
          X := RenderW * (1 + 2 * (Row div RowsPerColumn)) / 4;
          LabelAt(Caption, X, 110 + 29 * (Row mod RowsPerColumn), 17, 0.45);
        end
        else
          LabelAt(Caption, X, 110 + 29 * Row, 17);
        Inc(Row);
      end;
    if DelayMeasurement.HasResult then
      DrawDelayButton(DelayApplyButton)
    else
      LabelAt(Language.Translate('SLOT_DELAY_RETRY_HINT'), RenderW / 2, RenderH - 140, 16);
  end;
  DrawDelayButton(DelayCancelButton);
end;

procedure TScreenName.OnShow;
var
  I, Count: integer;
  PreviewEnd: real;
begin
  inherited;
  PreviewEnd := 0;
  if Goto_SingScreen and (CatSongs.Selected >= 0) and
     (CatSongs.Selected < Length(CatSongs.Song)) then
    ScreenSong.StartFinishedSong(CatSongs.Song[CatSongs.Selected], PreviewEnd);
  RemoteBridgeIPC.SendGameState('player_setup', 0, 0);
  AudioPlayback.SetVolume(EnsureRange(Ini.PreviewVolume, 0, 100) / 100);

  Ini.ReloadNames;
  RemoteBridgeIPC.RefreshRemoteInputs(true);
  if Party.bPartyGame then
  begin
    CountIndex := Ini.Players;
    UpdateSelectSlideOptions(PlayersCount, IPlayers, CountIndex);
  end
  else
  begin
    ScanMicDevices;
    CountIndex := LyricsOnlyIndex;
    if not LyricsOnly then
    begin
      Count := ConfirmedLocalPlayerCount;
      if Count < 0 then
      begin
        Count := 0;
        if Length(AudioInputProcessor.DeviceList) > 0 then
          Count := UIni.IPlayersVals[Ini.Players];
      end;
      if (ConfirmedLocalPlayerCount >= 0) or (Count > 0) or (HighestRemoteSlot > 0) then
        CountIndex := PhonesOnlyIndex + Count;
    end;
    UpdateAssignedPlayers(true);
  end;

  for I := 0 to UIni.IMaxPlayerCount-1 do
  begin
    PlayerNames[I] := Ini.Name[I];
    PlayerLevel[I] := Ini.PlayerLevel[I];
    PlayerAvatars[I] := GetArrayIndex(AvatarsMD5, Ini.PlayerAvatar[I]);
    // if it is -1 then the current saved md5 does not exist anymore (file has changed or was deleted entirely)
    // setting it to 0 just resets it to the colorized default avatar
    if (PlayerAvatars[I] = -1) then
    begin
      PlayerAvatars[I] := 0;
    end;
  end;

  AvatarTarget := PlayerAvatars[PlayerIndex];
  AvatarCurrent := AvatarTarget;

  RefreshPlayers;
  RefreshVoice;

  PlayerColorButton(Num[PlayerIndex]);

  SelectsS[PlayersCount].SetSelectOpt(CountIndex);

  Button[PlayerName].Text[0].Text := PlayerNames[PlayerIndex];

  isScrolling := false;
  if not OwnsMicPreview then MicPreviewCount := -1;
  UpdateMicActivity;

  Interaction := 0;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenName');
end;

procedure TScreenName.SetAvatarScroll;
var
  B:        integer;
  Angle:    real;
  Pos:      real;
  VS:       integer;
  Padding:  real;
  X:        real;
  Factor:   real;
begin

  VS := Length(AvatarsList);

  case NumVisibleAvatars of
    1: begin
        Factor := 0;
       end;
    3: begin
        Factor := 1;
       end;
    5: begin
        Factor := 1.5;
       end;
   end;

  // Update positions of all avatars
  for B := PlayerAvatarButton[0] to PlayerAvatarButton[High(AvatarsList)] do
  begin
    Button[B].Visible := true; // adjust visibility

    // Pos is the distance to the centered avatar in the range [-VS/2..+VS/2]
    Pos := (B - PlayerAvatarButton[0] - AvatarCurrent);
    if (Pos < -VS/2) then
      Pos := Pos + VS
    else if (Pos > VS/2) then
      Pos := Pos - VS;

    // Avoid overlapping of the front avatars.
    // Use an alternate position for the others.
    if (Abs(Pos) < (NumVisibleAvatars/2)) then
    begin
      if (NumVisibleAvatars > 1) then
      begin
        Angle := Pi * (Pos / Min(VS, NumVisibleAvatars)); // Range: (-1/4*Pi .. +1/4*Pi)

        Button[B].H := Abs(Theme.Name.PlayerAvatar.H * cos(Angle*0.8));
        Button[B].W := Abs(Theme.Name.PlayerAvatar.W * cos(Angle*0.8));

        //Button[B].Reflectionspacing := 15 * Button[B].H/Theme.Song.Cover.H;
        Button[B].DeSelectReflectionspacing := 15 * Button[B].H/Theme.Name.PlayerAvatar.H;

        Padding := (Button[B].W - Theme.Name.PlayerAvatar.W)/2;
        X := Sin(Angle*1.3) * 0.9;

        Button[B].X := Theme.Name.PlayerAvatar.X + (Theme.Name.PlayerAvatar.W * Factor + DistanceVisibleAvatars) * X - Padding;
        Button[B].Y := (Theme.Name.PlayerAvatar.Y  + (Theme.Name.PlayerAvatar.H - Abs(Theme.Name.PlayerAvatar.H * cos(Angle))) * 0.5);
        Button[B].Z := 0.95 - Abs(Pos) * 0.01;

        Button[B].Reflection := true;
        Button[B].Reflectionspacing := 2;

        if (B <> PlayerAvatarButton[PlayerAvatars[PlayerIndex]]) then
        begin
          Button[B].Texture.Int := 0.7;
        end
        else
        begin
          Button[B].Texture.Int := 1;
        end;
      end
      else
      begin
        Button[B].X := Theme.Name.PlayerAvatar.X;
        Button[B].Y := Theme.Name.PlayerAvatar.Y;
        Button[B].W := Theme.Name.PlayerAvatar.W;
        Button[B].H := Theme.Name.PlayerAvatar.H;

        AvatarCurrent := AvatarTarget;

        isScrolling := false;
      end

    end
    else
    begin
      Button[B].Visible := false;
    end;

  end;

end;

procedure TScreenName.SelectNext;
var
  VS:   integer;
begin

  VS := Length(AvatarsList);

  if VS > 0 then
  begin

    if (not isScrolling) and (VS > 0) then
    begin
      isScrolling := true;
    end;

    AvatarTarget := AvatarTarget + 1;

    // try to keep all at the beginning
    if AvatarTarget > VS-1 then
    begin
      AvatarTarget := AvatarTarget - VS;
      AvatarCurrent := AvatarCurrent - VS;
    end;
  end;

end;

procedure TScreenName.SelectPrev;
var
  VS:   integer;
begin

  VS := Length(AvatarsList);

  if VS > 0 then
  begin
    if (not isScrolling) and (VS > 0) then
    begin
      isScrolling := true;
    end;

    AvatarTarget := AvatarTarget - 1;

    // try to keep all at the beginning
    if AvatarTarget < 0 then
    begin
      AvatarTarget := AvatarTarget + VS;
      AvatarCurrent := AvatarCurrent + VS;
    end;
  end;

end;

// The card is a view of the existing controls. Names, avatars, colors,
// difficulty and voice assignments keep their normal input and persistence.
function TScreenName.CardRect(Index: integer): TPlayerSlotRect;
var Columns, Rows, PageSize, LocalIndex, Count: integer;
begin
  Columns := Theme.Name.Cards.Columns;
  PageSize := Columns * Theme.Name.Cards.Rows;
  Count := Min(PageSize, SelectedPlayerCount - (PlayerIndex div PageSize) * PageSize);
  Rows := Max(1, (Count + Columns - 1) div Columns);
  LocalIndex := Index mod PageSize;
  Result.W := Max(1, (Theme.Name.Cards.Area.W - (Columns - 1) * Theme.Name.Cards.Gap) div Columns);
  Result.H := Min(Theme.Name.Cards.MaxH,
    Max(1, (Theme.Name.Cards.Area.H - (Rows - 1) * Theme.Name.Cards.Gap) div Rows));
  Result.X := Theme.Name.Cards.Area.X + (LocalIndex mod Columns) * (Result.W + Theme.Name.Cards.Gap);
  Result.Y := Theme.Name.Cards.Area.Y + (LocalIndex div Columns) * (Result.H + Theme.Name.Cards.Gap);
end;

procedure TScreenName.UpdateMicActivity;
var
  I, Count, LocalCount: integer;
  Target, Threshold, Blend: single;
  NowTicks, LastInput: QWord;
  Clipped: boolean;
  C: TRGB;
begin
  Count := SelectedPlayerCount;
  LocalCount := -1;
  if not Party.bPartyGame then LocalCount := SelectedLocalPlayerCount;
  if (Count <> MicPreviewCount) or (LocalCount <> MicPreviewLocalCount) then
  begin
    if OwnsMicPreview then AudioInput.CaptureStop(true);
    OwnsMicPreview := false;
    MicPreviewCount := Count;
    MicPreviewLocalCount := LocalCount;
    FillChar(MicActivity, SizeOf(MicActivity), 0);
    FillChar(MicClippedUntil, SizeOf(MicClippedUntil), 0);
  end;
  // Retry after an outgoing singing screen releases its capture at fade end.
  if (Count > 0) and not AudioInput.IsCapturing then
  begin
    AudioInput.CaptureStart(Count, true, LocalCount);
    OwnsMicPreview := true;
  end;
  Threshold := IThresholdVals[EnsureRange(Ini.ThresholdIndex, 0, High(IThresholdVals))];
  NowTicks := GetTickCount64;
  for I := 0 to Count - 1 do
  begin
    Target := 0;
    if OwnsMicPreview and (Party.bPartyGame or
       not IsRosterGap(I)) then
    begin
      LastInput := AudioInputProcessor.Sound[I].LastInputTicks;
      if (LastInput <> 0) and (LastInput <= NowTicks) and
         (NowTicks - LastInput <= MicPreviewFreshMs) then
      begin
        Target := AudioInputProcessor.Sound[I].MaxSampleVolume(Clipped);
        if Clipped then MicClippedUntil[I] := NowTicks + MicClipHoldMs;
      end;
    end;
    // Ignore background hiss; brightening shows activity below clipping.
    Target := EnsureRange((Target - Threshold) / (1 - Threshold), 0, 1);
    if Target > MicActivity[I] then Blend := 1 - Exp(-Max(0, TimeSkip) / 0.04)
    else Blend := 1 - Exp(-Max(0, TimeSkip) / 0.25);
    MicActivity[I] := MicActivity[I] + (Target - MicActivity[I]) * Blend;
    C := MicColor(I);
    with Statics[PlayerCurrent[I]].Texture do
    begin
      ColR := C.R;
      ColG := C.G;
      ColB := C.B;
    end;
  end;
end;

function TScreenName.MicColor(PlayerID: integer): TRGB;
begin
  if GetTickCount64 < MicClippedUntil[PlayerID] then
    Exit(Default(TRGB));
  Result := GetPlayerColor(Num[PlayerID]);
  Result.R := Result.R + (1 - Result.R) * MicActivity[PlayerID];
  Result.G := Result.G + (1 - Result.G) * MicActivity[PlayerID];
  Result.B := Result.B + (1 - Result.B) * MicActivity[PlayerID];
end;

procedure TScreenName.DrawCards;
var I, First, Last, J: integer;
  R: TPlayerSlotRect;
  SX, SY, AvatarSide: real;
  Panel: TTexture;
  C: TRGB;
  LabelText: UTF8String;
  procedure Difficulty(PlayerID: integer);
  var K: integer; T: TTexture; C: TRGB; BaseX, BaseY, SegmentW: real;
    Bounds: TMouseOverRect;
  begin
    BaseX := Theme.Name.SelectPlayerLevel.X;
    BaseY := Theme.Name.SelectPlayerLevel.Y;
    SegmentW := (Theme.Name.Cards.Panel.W - 30) / 3;
    for K := 0 to 2 do
    begin
      if PlayerLevel[PlayerID] = K then
      begin
        T := SelectsS[PlayerSelectLevel].TextureSBG;
        Bounds := DifficultySegmentRect(PlayerID, K);
        T.X := Bounds.X; T.Y := Bounds.Y;
        T.W := Bounds.W; T.H := Bounds.H;
        if (PlayerID = PlayerIndex) and (Interaction = PlayerSelectLevelIID) then
          C := GetPlayerColor(Num[PlayerID])
        else begin C.R := 0.2; C.G := 0.21; C.B := 0.22; end;
        T.ColR := C.R; T.ColG := C.G; T.ColB := C.B;
        Renderer.DrawTexture(T);
      end;
      SetFontFamily(ResolveThemeFont(Theme.Name.Cards.NameText.FontFile, Theme.Name.Cards.NameText.Font));
      SetFontStyle(0); SetFontItalic(false); SetFontReflection(false, 0);
      SetFontSize(Max(8, Round(Theme.Name.SelectPlayerLevel.TextSize * SY)));
      if PlayerLevel[PlayerID] = K then SetFontColor(1, 1, 1, 1)
      else SetFontColor(0.5, 0.5, 0.5, 1);
      SetFontPos(R.X + (BaseX + (K + 0.5) * SegmentW) * SX - TextWidth(IDifficultyTranslated[K]) / 2,
        R.Y + (BaseY + 7) * SY);
      PrintText(IDifficultyTranslated[K]);
    end;
  end;
  function TextColor: TRGB;
  begin
    Result.R := Theme.Name.PlayerSelectTemplateText.ColR;
    Result.G := Theme.Name.PlayerSelectTemplateText.ColG;
    Result.B := Theme.Name.PlayerSelectTemplateText.ColB;
  end;
  procedure Caption(const Value: UTF8String; X, Y, Size: real; const C: TRGB);
  begin
    SetFontFamily(ResolveThemeFont(Theme.Name.Cards.NameText.FontFile, Theme.Name.Cards.NameText.Font));
    SetFontStyle(0); SetFontItalic(false); SetFontReflection(false, 0);
    SetFontSize(Max(8, Round(Size * SY)));
    SetFontColor(C.R, C.G, C.B, 1);
    SetFontPos(R.X + X * SX, R.Y + Y * SY);
    if (TextWidth(Value) > 0) and (TextWidth(Value) > R.W - X * SX - 8) then
      SetFontSize(Max(6, Round(Size * SY * Max(1, R.W - X * SX - 8) / TextWidth(Value))));
    PrintText(Value);
  end;
  procedure PlaceSlide(Index: integer; const Source: TThemeSelectSlide);
  var K: integer;
  begin
    with SelectsS[Index] do
    begin
      Texture.W := Source.W * SX; Texture.H := Source.H * SY;
      TextureSBG.H := Source.H * SY; SBGW := Source.SBGW * SX;
      Text.Size := Max(8, Round(Source.TextSize * SY));
      for K := 0 to High(TextOpt) do TextOpt[K].Size := Text.Size;
      SetX(R.X + Source.X * SX); SetY(R.Y + Source.Y * SY);
      // These setup slides show one option. Moving a slide does not regenerate
      // its option positions, so keep that option centered in its new card.
      for K := 0 to High(TextOpt) do
      begin
        TextOpt[K].X := TextureSBG.X + TextureSBG.W / 2;
        TextOpt[K].Align := 1;
      end;
      SetSelectOpt(SelectedOption);
    end;
  end;
begin
  First := (PlayerIndex div (Theme.Name.Cards.Columns * Theme.Name.Cards.Rows)) * Theme.Name.Cards.Columns * Theme.Name.Cards.Rows;
  Last := Min(SelectedPlayerCount - 1, First + Theme.Name.Cards.Columns * Theme.Name.Cards.Rows - 1);
  for I := First to Last do
  begin
    R := CardRect(I);
    SX := R.W / Max(1, Theme.Name.Cards.Panel.W);
    SY := R.H / Max(1, Theme.Name.Cards.Panel.H);
    Panel := Statics[CardPanel].Texture;
    Panel.X := R.X; Panel.Y := R.Y; Panel.W := R.W; Panel.H := R.H;
    Renderer.DrawTexture(Panel);
    if I = PlayerIndex then
    begin
      Panel := Statics[CardFocus].Texture;
      Panel.X := R.X - 2; Panel.Y := R.Y - 2; Panel.W := R.W + 4; Panel.H := R.H + 4;
      Renderer.DrawTexture(Panel);
    end;
    // Player labels are translated through the shared generated-label keys.
    LabelText := Language.Translate('OPTION_VALUE_PLAYER') + ' ' + IntToStr(I + 1);
    if Theme.Name.Cards.ShowLabel then Caption(LabelText, 60, 22, 10, TextColor);
    with Statics[PlayerCurrentAvatar[I]].Texture do
    begin
      // Fit a square avatar in physical pixels, including non-16:9 viewports.
      AvatarSide := Min(Theme.Name.Cards.Avatar.W * SX * GetLayoutScaleX,
        Theme.Name.Cards.Avatar.H * SY * GetLayoutScaleY);
      W := AvatarSide / Max(0.0001, GetLayoutScaleX);
      H := AvatarSide / Max(0.0001, GetLayoutScaleY);
      X := R.X + Theme.Name.Cards.Avatar.X * SX +
        (Theme.Name.Cards.Avatar.W * SX - W) / 2;
      Y := R.Y + Theme.Name.Cards.Avatar.Y * SY +
        (Theme.Name.Cards.Avatar.H * SY - H) / 2;
      ScaleMode := lsStretch;
      CornerRadius := Theme.Name.PlayerSelectTemplateAvatar.CornerRadius;
    end;
    Statics[PlayerCurrentAvatar[I]].Draw;
    C := MicColor(I);
    Panel := Statics[MicFrame].Texture;
    with Statics[PlayerCurrentAvatar[I]].Texture do
    begin
      Panel.X := X; Panel.Y := Y; Panel.W := W; Panel.H := H;
      Panel.Z := Z; Panel.Alpha := Alpha;
      Panel.ScaleMode := ScaleMode; Panel.CornerRadius := CornerRadius;
    end;
    // Initials themes use a circular default avatar; keep its outline circular.
    if Theme.Name.Cards.Initials and (PlayerAvatars[I] = 0) then
      Panel.CornerRadius := 0.5;
    Panel.OutlineWidth := 0.05;
    Panel.ColR := C.R; Panel.ColG := C.G; Panel.ColB := C.B;
    Renderer.DrawTexture(Panel);
    if Theme.Name.Cards.Initials and (PlayerAvatars[I] = 0) then
    begin
      LabelText := UTF8UpperCase(UTF8Copy(PlayerNames[I], 1, 1));
      SetFontFamily(Theme.Name.Cards.NameText.Font);
      SetFontStyle(1); SetFontSize(Max(8, Round(20 * SY)));
      SetFontColor(0.03, 0.04, 0.05, 1);
      SetFontPos(R.X + (Theme.Name.Cards.Avatar.X + Theme.Name.Cards.Avatar.W / 2) * SX - TextWidth(LabelText) / 2,
        R.Y + (Theme.Name.Cards.Avatar.Y + Theme.Name.Cards.Avatar.H / 2 - 10) * SY);
      PrintText(LabelText);
    end;
    if (I = PlayerIndex) and (Theme.Name.Cards.EditOutside or not Button[PlayerName].Visible) then
      Caption(DisplayPlayerName(I), Theme.Name.Cards.NameText.X,
        Theme.Name.Cards.NameText.Y, Theme.Name.Cards.NameText.Size, TextColor);
    if I = PlayerIndex then
    begin
      SY := CardEditorScaleY(I, R);
      if Theme.Name.Cards.EditOutside then
      begin
        R.X := 0; R.Y := 0; SX := 1; SY := 1;
      end;
      Button[PlayerName].W := Theme.Name.PlayerButtonName.W * SX;
      Button[PlayerName].H := Theme.Name.PlayerButtonName.H * SY;
      Button[PlayerName].X := R.X + Theme.Name.PlayerButtonName.X * SX;
      Button[PlayerName].Y := R.Y + Theme.Name.PlayerButtonName.Y * SY;
      Button[PlayerName].Text[0].Size := Max(8, Round(Theme.Name.PlayerButtonName.Text[0].Size * SY));
      Button[PlayerName].Draw;
      PlaceSlide(PlayerColor, Theme.Name.SelectPlayerColor);
      PlaceSlide(PlayerSelectLevel, Theme.Name.SelectPlayerLevel);
      PlaceSlide(PlayerSelectVoice, Theme.Name.SelectPlayerVoice);
      SelectsS[PlayerColor].Draw;
      if Theme.Name.Cards.LevelSegments then Difficulty(I)
      else SelectsS[PlayerSelectLevel].Draw;
      if SelectsS[PlayerSelectVoice].Visible then SelectsS[PlayerSelectVoice].Draw;
      // Reuse the existing avatar picker, without its large carousel.
      R := CardRect(I);
      SX := R.W / Max(1, Theme.Name.Cards.Panel.W);
      SY := R.H / Max(1, Theme.Name.Cards.Panel.H);
      with Statics[PlayerCurrentAvatar[I]].Texture do
      begin
        Button[PlayerAvatar].X := X; Button[PlayerAvatar].Y := Y;
        Button[PlayerAvatar].W := W; Button[PlayerAvatar].H := H;
      end;
      if Interaction = PlayerAvatarIID then
        Caption('< >', 20, 73, 12, GetPlayerColor(Num[I]));
    end
    else
    begin
      Caption(DisplayPlayerName(I), Theme.Name.Cards.NameText.X, Theme.Name.Cards.NameText.Y,
        Theme.Name.Cards.NameText.Size, TextColor);
      if not Theme.Name.Cards.EditOutside then
      begin
        Caption(IPlayerColorTranslated[Num[I] - 1], 75, 142, 14, GetPlayerColor(Num[I]));
        if Theme.Name.Cards.LevelSegments then Difficulty(I)
        else Caption(IDifficultyTranslated[PlayerLevel[I]], 75, 184, 14, TextColor);
      end;
    end;
  end;
  if SelectedPlayerCount > Theme.Name.Cards.Columns * Theme.Name.Cards.Rows then
  begin
    R := CardRect(First);
    SX := 1; SY := 1;
    Caption(Format('%d-%d / %d', [First + 1, Last + 1, SelectedPlayerCount]),
      0, Theme.Name.Cards.Area.H + 10, 13, TextColor);
  end;
  SelectsS[PlayersCount].Draw;
  for I := 0 to High(Statics) do
  begin
    J := 0;
    while (J < UIni.IMaxPlayerCount) and (I <> PlayerCurrent[J]) and
      (I <> PlayerCurrentAvatar[J]) do Inc(J);
    if J = UIni.IMaxPlayerCount then Statics[I].Draw;
  end;
  for I := 0 to High(Text) do
  begin
    J := 0;
    while (J < UIni.IMaxPlayerCount) and (I <> PlayerCurrentText[J]) do Inc(J);
    if J = UIni.IMaxPlayerCount then Text[I].Draw;
  end;
end;

function TScreenName.Draw: boolean;
var
  dx: real;
  dt: real;
  I, LocalCount: integer;
begin
  ScreenSong.UpdateTransitionPreview;
  if ScanMicDevices then
  begin
    UpdateAssignedPlayers(true);
    RefreshPlayers;
    RefreshProfile;
  end
  else
    UpdateAssignedPlayers;
  //inherited Draw;
  //heres a little Hack, that causes the Statics
  //are Drawn after the Buttons because of some Blending Problems.
  //This should cause no Problems because all Buttons on this screen
  //Has Z Position.
  DrawBG;

  if Ini.ReloadNames then
  begin
    OnShow;
    Ini.ReloadDelays;
  end;

  if isScrolling then
  begin
    dx := AvatarTarget - AvatarCurrent;
    dt := TimeSkip * 7;

    if dt > 1 then
      dt := 1;

    AvatarCurrent := AvatarCurrent + dx*dt;

    if SameValue(AvatarCurrent, AvatarTarget, 0.002) and (Length(AvatarsList) > 0) then
    begin
      isScrolling := false;
      AvatarCurrent := AvatarTarget;
    end;
  end;

  UpdateMicActivity;
  ScreenContinuousPlayback.Update;
  if Assigned(DelayMeasurement) then
  begin
    DelayMeasurement.Update;
    DrawDelayMeasurement;
    Exit(true);
  end;
  Text[DelayHintText].Visible := (SelectedPlayerCount > 0) and (Theme.Name.DelayHint.Size > 0);
  if Theme.Name.Cards.Enabled then
  begin
    DrawCards;
    DrawMicSelector;
    Result := true;
    Exit;
  end;
  if SelectedPlayerCount > 0 then SetAvatarScroll;

  // set current name = name in list
  if Button[PlayerName].Visible then
    Text[PlayerCurrentText[PlayerIndex]].Text := Button[PlayerName].Text[0].Text;

  //Instead of Draw FG Procedure:
  //We draw Buttons for our own
  for I := 0 to High(Button) do
    Button[I].Draw;

  // SelectsS
  for I := 0 to High(SelectsS) do
    if I <> PlayerMic then SelectsS[I].Draw;

  // Statics
  for I := 0 to High(Statics) do
    Statics[I].Draw;

  // and texts
  LocalCount := -1;
  if not Party.bPartyGame then LocalCount := SelectedLocalPlayerCount;
  for I := 0 to SelectedPlayerCount - 1 do
    if Statics[PlayerCurrentAvatar[I]].Visible and (Party.bPartyGame or
       not IsRosterGap(I)) then
      with Statics[PlayerCurrentAvatar[I]].Texture do
        DrawInputSourceBadge(PlayerInputSource(I, LocalCount), X, Y, W, H, ibsSetup, Alpha, ScaleMode);
  for I := 0 to High(Text) do
    Text[I].Draw;

  DrawMicSelector;
  Result := true;
end;

end.
