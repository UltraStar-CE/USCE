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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/screens/UScreenOptionsGame.pas $
 * $Id: UScreenOptionsGame.pas 2203 2010-03-16 19:25:13Z brunzelchen $
 *}

unit UScreenOptionsGame;

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
  UScreensong,
  USongs,
  UThemes,
  sdl2;

type
  TScreenOptionsGame = class(TOptionsMenu)
    private
      StatisticsViewLabels: array[0..1] of UTF8String;
      AgeCountryIndex: integer;
      AgeCountries: array of UTF8String;
      AgeCountryLabels: array of UTF8String;
      old_Language:  integer;
      old_SongMenu:  integer;
      old_Sorting:   integer;
      old_Tabs:      integer;
      AVDelayOptInt: integer;
      MicDelayOptInt:integer;
      AVDelaySelectNum:  integer;
      MicDelaySelectNum: integer;

      procedure Leave;
      procedure ReloadCurrentScreen;
      procedure ReloadAllScreens;
      procedure ReloadSongMenu;
      procedure UpdateCalculatedSelectSlides(Init: boolean);

    protected
      procedure LoadWidgets; override;

    public
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
  end;

const
  ID='ID_071';   //for help system

implementation

uses
  UConfig,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UUnicodeUtils,
  SysUtils, Classes;

type
  TGetTextFunc = function(var Param: integer; Offset: integer; Modify: boolean; OptText: PUtf8String): boolean;
  UTF8StringArray = array of UTF8String;
  InteractionID = (
    iLanguageSlide,
    iSongMenuSlide,
    iTabsSlide,
    iSortingSlide,
    iShowScoresSlide,
    iDebugSlide,
    iStatisticsViewSlide,
    iAgeCountrySlide,
    iAVDelaySlide,
    iMicDelaySlide,
    iBackButton
  );

function TScreenOptionsGame.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
begin
  Result := true;
  if PressedDown then
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
          Leave;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_RETURN:
        begin
          if SelInteraction = ord(iBackButton) then
            Leave;
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
          UpdateCalculatedSelectSlides(false);
          if (SelInteraction = ord(iLanguageSlide)) then
          begin
            ReloadCurrentScreen;
          end;
        end;
      SDLK_LEFT:
        begin
          if Interactions[SelInteraction].Typ = iSelectS then
          begin
            AudioPlayback.PlaySound(SoundLib.Option);
            InteractDec;
          end;
          UpdateCalculatedSelectSlides(false);
          if (SelInteraction = ord(iLanguageSlide)) then
          begin
            ReloadCurrentScreen;
          end;
        end;
    end;
  end;
end;

procedure CalculateSelectSlide(Init: boolean; GetText: TGetTextFunc; var Param: integer; var OptInt: integer; var Texts: UTF8StringArray);
var
  Idx: integer;
  NumOpts: integer;
begin
  if not GetText(Param, 0, true, nil) then
  begin
    SetLength(Texts, 0);
    Exit;
  end;
  if GetText(Param, -1, false, nil) then
    Idx := 1
  else
    Idx := 0;
  if not Init then
  begin
    if OptInt = Idx then
      Exit;
    GetText(Param, OptInt - Idx, true, nil);
    if GetText(Param, -1, false, nil) then
      Idx := 1
    else
      Idx := 0;
  end;
  OptInt := Idx;
  if GetText(Param, 1, false, nil) then
    NumOpts := Idx + 2
  else
    NumOpts := Idx + 1;
  SetLength(Texts, NumOpts);
  for Idx := 0 to High(Texts) do
    GetText(Param, Idx - OptInt, false, @Texts[Idx]);
end;

function GetAVDelayOptText(var Param: integer; Offset: integer; Modify: boolean; OptText: PUTF8String): boolean;
begin
  if OptText <> nil then
    OptText^ := Format('%d ms', [Param + Offset * 10]);
  if Modify then
    Param := Param + Offset * 10;
  Result := true;
end;

function GetMicDelayOptText(var Param: integer; Offset: integer; Modify: boolean; OptText: PUTF8String): boolean;
begin
  if Param + Offset * 10 < 0 then
    Result := false
  else
  begin
    if OptText <> nil then
      OptText^ := Format('%d ms', [Param + Offset * 10]);
    if Modify then
      Param := Param + Offset * 10;
    Result := true;
  end;
end;

procedure TScreenOptionsGame.UpdateCalculatedSelectSlides(Init: boolean);
begin
  CalculateSelectSlide(Init, @GetAVDelayOptText, Ini.AVDelay, AVDelayOptInt, IAVDelay);
  CalculateSelectSlide(Init, @GetMicDelayOptText, Ini.MicDelay, MicDelayOptInt, IMicDelay);
  if Init then
  begin
    AVDelaySelectNum := AddSelectSlide('SING_OPTIONS_GAME_AVDELAY', AVDelayOptInt, IAVDelay);
    MicDelaySelectNum := AddSelectSlide('SING_OPTIONS_GAME_MICDELAY', MicDelayOptInt, IMicDelay);
  end
  else
  begin
    UpdateSelectSlideOptions(AVDelaySelectNum, IAVDelay, AVDelayOptInt);
    UpdateSelectSlideOptions(MicDelaySelectNum, IMicDelay, MicDelayOptInt);
  end;
end;

constructor TScreenOptionsGame.Create;
begin
  inherited Create;
  Description := Language.Translate('SING_OPTIONS_GAME_DESC');
  WhereAmI := Language.Translate('SING_OPTIONS_GAME_WHEREAMI');
  Load;
end;

procedure TScreenOptionsGame.OnShow;
begin
  inherited;

  // save current settings in order to determine if a refresh is required
  old_Language := Ini.Language;
  old_SongMenu := Ini.SongMenu;
  old_Sorting  := Ini.Sorting;
  old_Tabs     := Ini.Tabs;

  Interaction := 0;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenOptionsGame');
end;

procedure TScreenOptionsGame.Leave;
begin
  Ini.AgeCountry := AgeCountries[AgeCountryIndex];
  Ini.Save;
  ReloadAllScreens;
  ReloadSongMenu;

  AudioPlayback.PlaySound(SoundLib.Back);
  FadeTo(@ScreenOptions);
end;

procedure TScreenOptionsGame.ReloadCurrentScreen;
begin
  Ini.AgeCountry := AgeCountries[AgeCountryIndex];
  ScreenOptionsGame.Free;
  Language.ChangeLanguage(ILanguage[Ini.Language]);
  Ini.TranslateOptionValues;
  Theme.LoadTheme(Ini.Theme, Ini.Color);
  ScreenOptionsGame := TScreenOptionsGame.Create;
end;

procedure TScreenOptionsGame.ReloadAllScreens;
begin
  // Reload all screens after language changed
  if (old_Language <> Ini.Language) then
  begin
    UGraphic.UnloadScreens;

    Theme.LoadTheme(Ini.Theme, Ini.Color);
    UGraphic.LoadScreens(USCEVersionStr);

    old_Language := Ini.Language;
    old_SongMenu := Ini.SongMenu;
    old_Sorting  := Ini.Sorting;
    old_Tabs     := Ini.Tabs;
  end;
end;

procedure TScreenOptionsGame.ReloadSongMenu;
begin
  if (Ini.Sorting <> old_Sorting) or (Ini.Tabs <> old_Tabs) or (old_SongMenu <> Ini.SongMenu) then
  begin
    Ini.TabsAtStartup := Ini.Tabs;
    Theme.ThemeSongReload;
    ScreenSong.Free;
    ScreenSong := TScreenSong.Create;
  end;
end;

procedure TScreenOptionsGame.LoadWidgets;
const
  CountryCodes = 'AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW';
var Codes: TStringList; I: integer;
begin
  Codes := TStringList.Create;
  try
    Codes.Delimiter := ' ';
    Codes.DelimitedText := CountryCodes;
    // Keep an explicitly configured rating authority available as well.
    if (Ini.AgeCountry <> '') and (Codes.IndexOf(Ini.AgeCountry) < 0) then
      Codes.Add(Ini.AgeCountry);
    SetLength(AgeCountries, Codes.Count + 1);
    SetLength(AgeCountryLabels, Codes.Count + 1);
    AgeCountries[0] := '';
    AgeCountryLabels[0] := Language.Translate('OPTION_VALUE_AGE_DEFAULT');
    AgeCountryIndex := 0;
    for I := 0 to Codes.Count - 1 do
    begin
      AgeCountries[I + 1] := Codes[I];
      AgeCountryLabels[I + 1] := Codes[I];
      if Codes[I] = Ini.AgeCountry then AgeCountryIndex := I + 1;
    end;
  finally
    Codes.Free;
  end;
  // when editing this, also update the InteractionID enum declaration
  AddSelectSlide('SING_OPTIONS_GAME_LANGUAGE', Ini.Language, ILanguageTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_SONGMENU', Ini.SongMenu, ISongMenuTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_TABS', Ini.Tabs, ITabsTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_SORTING', Ini.Sorting, ISortingTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_SHOWSCORES', Ini.ShowScores, IShowScoresTranslated);
  AddSelectSlide('SING_OPTIONS_GAME_DEBUG', Ini.Debug, IDebugTranslated);
  StatisticsViewLabels[0] := Language.Translate('OPTION_VALUE_STATISTICS_REDUCED');
  StatisticsViewLabels[1] := Language.Translate('OPTION_VALUE_STATISTICS_FULL');
  AddSelectSlide('SING_OPTIONS_GAME_STATISTICS', Ini.StatisticsView, StatisticsViewLabels);
  AddSelectSlide('SING_OPTIONS_GAME_AGE_COUNTRY', AgeCountryIndex, AgeCountryLabels);
  UpdateCalculatedSelectSlides(true);
end;

end.
