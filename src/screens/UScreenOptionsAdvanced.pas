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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenOptionsAdvanced.pas $
 * $Id: UScreenOptionsAdvanced.pas 2338 2010-05-03 21:58:30Z k-m_schindler $
 *}

unit UScreenOptionsAdvanced;

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
  UThemes,
  sdl2;

type
  TScreenOptionsAdvanced = class(TOptionsMenu)
    public
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
    private
      SyncerPortButton, SyncerFolderButton: integer;
    protected
      procedure LoadWidgets; override;
  end;

const
  ID='ID_078';   //for help system

implementation

uses
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UUnicodeUtils,
  SysUtils, USyncerWeb, USongs, UPath;

type
  InteractionID = (
    iScreenFadeSlide,
    iEffectSingSlide,
    iOnSongClickSlide,
    iAskBeforeDelSlide,
    iPartyPopupSlide,
    iSingScoresSlide,
    iDuetScoresSlide,
    iTopScoresSlide,
    iBackButton
  );

procedure SyncerFolderConfirmed(Value: boolean; Data: Pointer);
var Folder: IPath;
begin
  if not Value then Exit;
  Folder := TSyncerClient.SongFolder;
  if Folder.IsDirectory and Ini.AddSongDirectory(Folder) then
    Songs.RequestRefresh(Folder);
end;

procedure SyncerPortEntered(Value: boolean; Data: Pointer);
var Port: integer;
begin
  if not Value or (Trim(ScreenPopupInsertUser.Username) = '') then Exit;
  Port := StrToIntDef(Trim(ScreenPopupInsertUser.Username), 0);
  if (Port < 1) or (Port > 65535) then
  begin
    ScreenPopupError.ShowPopup(Language.Translate('SYNCER_INVALID_PORT'));
    Exit;
  end;
  Ini.SyncerPort := Port;
  Ini.Save;
end;

function TScreenOptionsAdvanced.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
var Folder: IPath;
begin
  Result := true;
  if (PressedDown) then
  begin // Key Down
    // check normal keys
    case PressedKey of
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
          FadeTo(@ScreenOptions);
        end;
      SDLK_TAB:
      begin
        ScreenPopupHelp.ShowPopup();
      end;
      SDLK_RETURN:
        begin
          if Interactions[SelInteraction].Typ = iButton then
          begin
            if Interactions[SelInteraction].Num = SyncerPortButton then
            begin
              ScreenPopupInsertUser.ShowTextPrompt(
                Format(Language.Translate('SYNCER_CURRENT_PORT'), [Ini.SyncerPort]),
                'SYNCER_PORT_HINT', Language.Translate('FILTER_PRESET_SAVE'),
                @SyncerPortEntered, nil, '', 'SYNCER_PORT');
              Exit;
            end;
            if Interactions[SelInteraction].Num = SyncerFolderButton then
            begin
              Folder := TSyncerClient.SongFolder;
              if Folder.IsDirectory then
                ScreenPopupCheck.ShowPopup(Format(Language.Translate('SYNCER_CONFIRM_FOLDER'), [Folder.ToUTF8]),
                  @SyncerFolderConfirmed, nil)
              else
                ScreenPopupInfo.ShowPopup(Language.Translate('SYNCER_FOLDER_UNKNOWN'));
              Exit;
            end;
            Ini.Save;
            AudioPlayback.PlaySound(SoundLib.Back);
            FadeTo(@ScreenOptions);
          end;
        end;
      SDLK_DOWN:
        InteractNext;
      SDLK_UP :
        InteractPrev;
      SDLK_RIGHT:
        begin
          if Interactions[SelInteraction].Typ = iSelectS then
          begin
            AudioPlayback.PlaySound(SoundLib.Option);
            InteractInc;
          end;
        end;
      SDLK_LEFT:
        begin
          if Interactions[SelInteraction].Typ = iSelectS then
          begin
            AudioPlayback.PlaySound(SoundLib.Option);
            InteractDec;
          end;
        end;
    end;
  end;
end;

constructor TScreenOptionsAdvanced.Create;
begin
  inherited Create;
  Description := Language.Translate('SING_OPTIONS_ADVANCED_DESC');
  WhereAmI := Language.Translate('SING_OPTIONS_ADVANCED_WHEREAMI');
  Load;
  Interaction := 0;
end;

procedure TScreenOptionsAdvanced.OnShow;
begin
  inherited;

  Interaction := 0;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenOptionsAdvanced');
end;

procedure TScreenOptionsAdvanced.LoadWidgets;
var
  NoteType: TNoteType;
  Weight: integer;
  DefaultSuffix: UTF8String;
  WeightOptions: array[0..MaxScoreFactor] of UTF8String;
begin
  AddSelectSlide('SING_OPTIONS_ADVANCED_SCREENFADE', Ini.ScreenFade, IScreenFadeTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_EFFECTSING', Ini.EffectSing, IEffectSingTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_ONSONGCLICK', Ini.OnSongClick, IOnSongClickTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_ASKBEFOREDEL', Ini.AskBeforeDel, IAskbeforeDelTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_PARTYPOPUP', Ini.PartyPopup, IPartyPopupTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_SINGSCORES', Ini.SingScores, ISingScoresTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_DUETSCORES', Ini.DuetScores, IDuetScoresTranslated);
  AddSelectSlide('SING_OPTIONS_ADVANCED_TOPSCORES', Ini.TopScores, ITopScoresTranslated);

  DefaultSuffix := ' (' + Language.Translate('OPTION_VALUE_DEFAULT') + ')';
  for Weight := Low(WeightOptions) to High(WeightOptions) do
    WeightOptions[Weight] := IntToStr(Weight) + '%';

  AddSection('SYNCER_SECTION');
  AddSelectSlide('EXTERNAL_SONG_SEARCH', Ini.ExternalSongSearch,
    [Language.Translate('OPTION_VALUE_OFF'), Language.Translate('OPTION_VALUE_ON')]);
  SyncerPortButton := AddButton('SYNCER_PORT');
  SyncerFolderButton := AddButton('SYNCER_ADD_FOLDER');

  AddSection('SING_OPTIONS_ADVANCED_SCORING');
  for NoteType := Low(TNoteType) to High(TNoteType) do
  begin
    Weight := StandardScoreFactor[NoteType];
    WeightOptions[Weight] := WeightOptions[Weight] + DefaultSuffix;
    AddSelectSlide('SING_OPTIONS_ADVANCED_SCORE_WEIGHT_' +
      UpperCase(ScoreFactorName[NoteType]), ScoreFactor[NoteType], WeightOptions);
    WeightOptions[Weight] := IntToStr(Weight) + '%';
  end;
end;

end.
