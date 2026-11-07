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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenOptionsSound.pas $
 * $Id: UScreenOptionsSound.pas 3124 2015-08-23 03:31:49Z basisbit $
 *}

unit UScreenOptionsSound;

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
  UMusic,
  MidiOut,
  UThemes,
  sdl2;

type
  TScreenOptionsSound = class(TOptionsMenu)
  private
    SoundPreview: TMidiOutput;
    LastSynthTone, LastClickSound: Integer;
    AudioVolumeSelectId: integer;
    BackgroundVolumeSelectId: integer;
    VocalsVolumeSelectId: integer;
    SfxVolumeSelectId: integer;
    PreviewVolumeSelectId: integer;
    procedure PreviewSoundChoice;
    function AddVolumeSlider(const Text: UTF8String; var Data: integer): integer;
    procedure ApplyRealtimeSoundSettings(UpdatePartialVocalsVolume: boolean = false);
    function IsVolumeSlider(SelectId: integer): boolean;
    function CurrentVolumeSelectId: integer;
    function StepVolumeSlider(Delta: integer): boolean;
    procedure UpdateVolumeSliderFromIni(SelectId, Value: integer);
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure OnHide; override;
    function ParseInput(PressedKey: Cardinal; CharCode: UCS4Char;
      PressedDown: boolean; Repeated: boolean = false): boolean; override;
    function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
    procedure OnShow; override;
    procedure SyncVolumeSlidersFromIni;
  protected
    procedure LoadWidgets; override;
  end;

const
  ID='ID_073';   //for help system

implementation

uses
  UGraphic,
  UMenuSelectSlide,
  UHelp,
  ULanguage,
  ULog,
  UUnicodeUtils,
  SysUtils,
  Math;

var
  VolumePercentOptions: array of UTF8String;

procedure EnsureVolumePercentOptions;
var
  I: integer;
begin
  if Length(VolumePercentOptions) > 0 then
    Exit;

  SetLength(VolumePercentOptions, 101);
  for I := 0 to High(VolumePercentOptions) do
    VolumePercentOptions[I] := IntToStr(I) + '%';
end;

type
  InteractionID = (
    iVoicePassthroughSlide,
    iBackgroundMusicSlide,
    iBackgroundMusicVolumeSlide,
    iClickAssistSlide,
    iSynthToneSlide,
    iClickSoundSlide,
    iReplayGainSlide,
    iAudioVolumeSlide,
    iVocalsVolumeSlide,
    iSfxVolumeSlide,
    iPreviewVolumeSlide,
    iPreviewFadingSlide,
    iEndedSongActionSlide,
    iBackButton
  );

function TScreenOptionsSound.ParseInput(PressedKey: cardinal;
  CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
var
  PrevVocalsVolume: integer;
begin
  Result := true;
  PrevVocalsVolume := Ini.VocalsVolume;

  if (PressedDown) then
  begin // Key Down
    case PressedKey of
      SDLK_Q:
      begin
        Result := false;
        Exit;
      end;
    end;

    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE:
      begin
        Ini.Save;
        AudioPlayback.PlaySound(SoundLib.Back);
        FadeTo(@ScreenOptions);
      end;
      SDLK_TAB: InteractTab;
      SDLK_F1:
      begin
        ScreenPopupHelp.ShowPopup();
      end;
      SDLK_K:
      begin
        ToggleVocalsVolume;
        AudioPlayback.PlaySound(SoundLib.Option);
        SyncVolumeSlidersFromIni;
        Exit;
      end;
      SDLK_RETURN:
      begin
        if SelInteraction = ord(iBackButton) then
        begin
          Ini.Save;
          AudioPlayback.PlaySound(SoundLib.Back);
          FadeTo(@ScreenOptions);
        end;
      end;
      SDLK_DOWN:
        InteractNext;
      SDLK_UP:
        InteractPrev;
      SDLK_RIGHT:
      begin
        if (SelInteraction >= 0) and (SelInteraction <= High(Interactions)) and
            (Interactions[SelInteraction].Typ = iSelectS) then
        begin
          if StepVolumeSlider(1) then
            AudioPlayback.PlaySound(SoundLib.Option)
          else
          begin
            if (SelInteraction <> Ord(iSynthToneSlide)) and
               (SelInteraction <> Ord(iClickSoundSlide)) then
              AudioPlayback.PlaySound(SoundLib.Option);
            InteractInc;
          end;
        end;
      end;
      SDLK_LEFT:
      begin
        if (Interactions[SelInteraction].Typ = iSelectS) then
        begin
          if StepVolumeSlider(-1) then
            AudioPlayback.PlaySound(SoundLib.Option)
          else
          begin
            if (SelInteraction <> Ord(iSynthToneSlide)) and
               (SelInteraction <> Ord(iClickSoundSlide)) then
              AudioPlayback.PlaySound(SoundLib.Option);
            InteractDec;
          end;
        end;
      end;
    end;
  end;

  ApplyRealtimeSoundSettings(Ini.VocalsVolume <> PrevVocalsVolume);
  SyncVolumeSlidersFromIni;
end;

function TScreenOptionsSound.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  PrevVocalsVolume: integer;
begin
  PrevVocalsVolume := Ini.VocalsVolume;
  Result := inherited ParseMouse(MouseButton, BtnDown, X, Y);
  ApplyRealtimeSoundSettings(Ini.VocalsVolume <> PrevVocalsVolume);
  SyncVolumeSlidersFromIni;
end;

constructor TScreenOptionsSound.Create;
begin
  inherited Create;
  AudioVolumeSelectId := -1;
  BackgroundVolumeSelectId := -1;
  VocalsVolumeSelectId := -1;
  SfxVolumeSelectId := -1;
  PreviewVolumeSelectId := -1;
  Description := Language.Translate('SING_OPTIONS_SOUND_DESC');
  WhereAmI := Language.Translate('SING_OPTIONS_SOUND_WHEREAMI');
  Load;
end;

destructor TScreenOptionsSound.Destroy;
begin
  FreeAndNil(SoundPreview);
  inherited;
end;

procedure TScreenOptionsSound.OnHide;
begin
  FreeAndNil(SoundPreview);
  inherited;
end;

procedure TScreenOptionsSound.PreviewSoundChoice;
var ToneChanged, ClickChanged: Boolean;
begin
  ToneChanged := Ini.SynthTone <> LastSynthTone;
  ClickChanged := Ini.ClickSound <> LastClickSound;
  LastSynthTone := Ini.SynthTone;
  LastClickSound := Ini.ClickSound;
  if not (ToneChanged or ClickChanged) then Exit;
  if SoundPreview = nil then
  begin
    SoundPreview := TMidiOutput.Create(nil);
    if not SoundPreview.Open then
    begin
      FreeAndNil(SoundPreview);
      Exit;
    end;
  end;
  SoundPreview.Stop;
  SoundPreview.SetPosition(0);
  SoundPreview.SetVolume(Ini.SfxVolume / 100);
  if ToneChanged then
  begin
    SoundPreview.QueueNoteOn(69, 110, 0);
    SoundPreview.QueueNoteOff(69, 0.5);
  end
  else
    SoundPreview.QueueClick(110, 0);
  SoundPreview.Play;
end;

procedure TScreenOptionsSound.OnShow;
begin
  inherited;
  Interaction := 0;
  LastSynthTone := Ini.SynthTone;
  LastClickSound := Ini.ClickSound;
  ApplyRealtimeSoundSettings;
  SyncVolumeSlidersFromIni;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenOptionsSound');
end;

procedure TScreenOptionsSound.LoadWidgets;
begin
  // when editing this, also update the InteractionID enum declaration
  AddSelectSlide('SING_OPTIONS_SOUND_VOICEPASSTHROUGH', Ini.VoicePassthrough, IVoicePassthroughTranslated);
  AddSelectSlide('SING_OPTIONS_SOUND_BACKGROUNDMUSIC', Ini.BackgroundMusicOption, IBackgroundMusicTranslated);
  BackgroundVolumeSelectId := AddVolumeSlider('SING_OPTIONS_SOUND_BACKGROUNDMUSICVOLUME', Ini.BackgroundMusicVolume);
  AddSelectSlide('SING_OPTIONS_SOUND_CLICK_ASSIST', Ini.ClickAssist, IClickAssistTranslated);
  AddSelectSlide('SING_OPTIONS_SOUND_SYNTH_TONE', Ini.SynthTone, ISynthToneTranslated);
  AddSelectSlide('SING_OPTIONS_SOUND_CLICK_SOUND', Ini.ClickSound, IClickSoundTranslated);
  AddSelectSlide('SING_OPTIONS_SOUND_MUSICAUTOGAIN', Ini.ReplayGain, IReplayGainTranslated);
  AudioVolumeSelectId := AddVolumeSlider('SING_OPTIONS_SOUND_AUDIOVOLUME', Ini.AudioVolume);
  VocalsVolumeSelectId := AddVolumeSlider('SING_OPTIONS_SOUND_VOCALSVOLUME', Ini.VocalsVolume);
  SfxVolumeSelectId := AddVolumeSlider('SING_OPTIONS_SOUND_SFXVOLUME', Ini.SfxVolume);
  PreviewVolumeSelectId := AddVolumeSlider('SING_OPTIONS_SOUND_PREVIEWVOLUME', Ini.PreviewVolume);
  AddSelectSlide('SING_OPTIONS_SOUND_PREVIEWFADING', Ini.PreviewFading, IPreviewFadingTranslated);
  AddSelectSlide('SING_OPTIONS_SOUND_ENDED_SONG', Ini.EndedSongAction, IEndedSongActionTranslated);
  SyncVolumeSlidersFromIni;
end;

function TScreenOptionsSound.AddVolumeSlider(const Text: UTF8String; var Data: integer): integer;
begin
  EnsureVolumePercentOptions;
  Data := EnsureRange(Data, 0, High(VolumePercentOptions));
  Result := AddSelectSlide(Text, Data, VolumePercentOptions);
end;

procedure TScreenOptionsSound.UpdateVolumeSliderFromIni(SelectId, Value: integer);
begin
  if (SelectId < 0) or (SelectId > High(SelectsS)) then
    Exit;

  EnsureVolumePercentOptions;
  Value := EnsureRange(Value, 0, High(VolumePercentOptions));
  if SelectsS[SelectId].SelectedOption <> Value then
    SelectsS[SelectId].SelectedOption := Value;
end;

procedure TScreenOptionsSound.SyncVolumeSlidersFromIni;
begin
  UpdateVolumeSliderFromIni(BackgroundVolumeSelectId, Ini.BackgroundMusicVolume);
  UpdateVolumeSliderFromIni(AudioVolumeSelectId, Ini.AudioVolume);
  UpdateVolumeSliderFromIni(VocalsVolumeSelectId, Ini.VocalsVolume);
  UpdateVolumeSliderFromIni(SfxVolumeSelectId, Ini.SfxVolume);
  UpdateVolumeSliderFromIni(PreviewVolumeSelectId, Ini.PreviewVolume);
end;

function TScreenOptionsSound.IsVolumeSlider(SelectId: integer): boolean;
begin
  Result := (SelectId = AudioVolumeSelectId) or
            (SelectId = BackgroundVolumeSelectId) or
            (SelectId = VocalsVolumeSelectId) or
            (SelectId = SfxVolumeSelectId) or
            (SelectId = PreviewVolumeSelectId);
end;

function TScreenOptionsSound.CurrentVolumeSelectId: integer;
begin
  Result := -1;
  if (SelInteraction < 0) or (SelInteraction > High(Interactions)) then
    Exit;

  if Interactions[SelInteraction].Typ <> iSelectS then
    Exit;

  if IsVolumeSlider(Interactions[SelInteraction].Num) then
    Result := Interactions[SelInteraction].Num;
end;

function TScreenOptionsSound.StepVolumeSlider(Delta: integer): boolean;
const
  StepSize = 10;
var
  SelectId: integer;
  Slider: TSelectSlide;
  Current: integer;
  Target: integer;
  MaxIndex: integer;
begin
  Result := false;
  if Delta = 0 then
    Exit;

  SelectId := CurrentVolumeSelectId;
  if SelectId < 0 then
    Exit;

  Slider := SelectsS[SelectId];
  if Slider = nil then
    Exit;

  MaxIndex := High(Slider.TextOptT);
  if MaxIndex < 0 then
    Exit;

  Current := Slider.SelectedOption;

  if Delta > 0 then
  begin
    Target := ((Current + StepSize - 1) div StepSize) * StepSize;
    if Target <= Current then
      Target := Target + StepSize;
  end
  else
  begin
    Target := (Current div StepSize) * StepSize;
    if Target >= Current then
      Target := Target - StepSize;
  end;

  Target := EnsureRange(Target, 0, MaxIndex);
  if Target = Current then
    Exit;

  Slider.SetSelectOpt(Target);
  Result := true;
end;

procedure TScreenOptionsSound.ApplyRealtimeSoundSettings(UpdatePartialVocalsVolume: boolean);
var
  MusicOptionValue: integer;
begin
  PreviewSoundChoice;
  SetAudioVolumePercent(Ini.AudioVolume);

  SetVocalsVolumePercent(Ini.VocalsVolume, UpdatePartialVocalsVolume);

  SetSfxVolumePercent(Ini.SfxVolume);

  SetBackgroundMusicVolumePercent(Ini.BackgroundMusicVolume);

  SetPreviewVolumePercent(Ini.PreviewVolume);

  MusicOptionValue := EnsureRange(Ini.BackgroundMusicOption,
    Ord(Low(TBackgroundMusicOption)), Ord(High(TBackgroundMusicOption)));
  if TBackgroundMusicOption(MusicOptionValue) = bmoOn then
    SoundLib.StartBgMusic
  else
    SoundLib.PauseBgMusic;
end;

end.
