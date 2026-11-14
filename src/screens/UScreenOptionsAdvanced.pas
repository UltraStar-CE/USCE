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

{$IFDEF DARWIN}
  {$modeswitch objectivec1}
{$ENDIF}

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
      EditorPathButton: integer;
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
  SysUtils
  {$IF Defined(WINDOWS)}, Windows, CommDlg
  {$ELSEIF Defined(DARWIN)}, CocoaAll, UPath
  {$ELSEIF Defined(UNIX)}, BaseUnix, Process, UPath
  {$ENDIF};

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

{$IF Defined(WINDOWS)}
type PEditorFilename = ^TOpenFilenameW;

function ChooseEditorFile(Dialog: PEditorFilename): BOOL; stdcall;
  external 'comdlg32.dll' name 'GetOpenFileNameW';

function PickEditorFile(out Selected: UTF8String): boolean;
var
  Dialog: TOpenFilenameW;
  Filename: array[0..32767] of WideChar;
  CurrentPath: UnicodeString;
begin
  FillChar(Dialog, SizeOf(Dialog), 0);
  FillChar(Filename, SizeOf(Filename), 0);
  CurrentPath := Copy(UTF8Decode(Ini.ExternalSongEditorPath), 1, High(Filename));
  if CurrentPath <> '' then
    Move(CurrentPath[1], Filename[0], Length(CurrentPath) * SizeOf(WideChar));
  Dialog.lStructSize := SizeOf(Dialog);
  Dialog.hwndOwner := GetActiveWindow;
  Dialog.lpstrFilter := 'Applications (*.exe)'#0'*.exe'#0#0;
  Dialog.lpstrFile := @Filename[0];
  Dialog.nMaxFile := Length(Filename);
  Dialog.Flags := OFN_FILEMUSTEXIST or OFN_PATHMUSTEXIST or OFN_NOCHANGEDIR;
  Result := ChooseEditorFile(@Dialog);
  if Result then
    Selected := UTF8Encode(UnicodeString(PWideChar(@Filename[0])));
end;
{$ELSEIF Defined(DARWIN)}
function PickEditorFile(out Selected: UTF8String): boolean;
var
  Panel: NSOpenPanel;
  SelectedURL, ExecutableURL: NSURL;
  Bundle: NSBundle;
  Folder: UTF8String;
begin
  Result := false;
  Panel := NSOpenPanel.openPanel;
  Panel.setTitle(NSString.stringWithUTF8String(PChar(Language.Translate('EXTERNAL_SONG_EDITOR_PATH'))));
  Panel.setCanChooseFiles(true);
  Panel.setCanChooseDirectories(false);
  Panel.setTreatsFilePackagesAsDirectories(false);
  Panel.setAllowsMultipleSelection(false);
  if Ini.ExternalSongEditorPath <> '' then
  begin
    Folder := Path(Ini.ExternalSongEditorPath).GetParent.ToUTF8;
    if SameText(ExtractFileName(ExcludeTrailingPathDelimiter(Folder)), 'MacOS') then
    begin
      Folder := Path(Folder).GetParent.GetParent.ToUTF8;
      if SameText(ExtractFileExt(ExcludeTrailingPathDelimiter(Folder)), '.app') then
        Folder := Path(Folder).GetParent.ToUTF8
      else
        Folder := Path(Ini.ExternalSongEditorPath).GetParent.ToUTF8;
    end;
    Panel.setDirectoryURL(NSURL.fileURLWithPath_isDirectory(NSString.stringWithUTF8String(PChar(Folder)), true));
  end;
  if Panel.runModal <> NSModalResponseOK then Exit;

  SelectedURL := Panel.URL;
  if SelectedURL = nil then Exit;
  Selected := UTF8String(SelectedURL.fileSystemRepresentation);
  if LowerCase(ExtractFileExt(ExcludeTrailingPathDelimiter(Selected))) = '.app' then
  begin
    Bundle := NSBundle.bundleWithURL(SelectedURL);
    if Bundle = nil then Exit;
    ExecutableURL := Bundle.executableURL;
    if ExecutableURL = nil then Exit;
    Selected := UTF8String(ExecutableURL.fileSystemRepresentation);
  end;
  Result := Path(Selected).IsFile;
end;
{$ELSEIF Defined(UNIX)}
function FindEditorPicker(KDE: boolean): string;
begin
  if KDE then
    Result := FileSearch('kdialog', GetEnvironmentVariable('PATH'), false)
  else
    Result := FileSearch('zenity', GetEnvironmentVariable('PATH'), false);
  if (Result = '') or not Path(Result).IsAbsolute or (fpAccess(PChar(Result), X_OK) <> 0) then
    Result := '';
end;

function PickEditorFile(const Picker: string; KDE: boolean; out Selected: UTF8String): boolean;
var
  Title, StartPath, Output: string;
begin
  Title := Language.Translate('EXTERNAL_SONG_EDITOR_PATH');
  StartPath := Ini.ExternalSongEditorPath;
  if StartPath = '' then StartPath := IncludeTrailingPathDelimiter(GetUserDir);
  if KDE then
    Result := RunCommand(Picker, ['--title', Title, '--getopenfilename', StartPath], Output, [poRunIdle])
  else
    Result := RunCommand(Picker, ['--title=' + Title, '--file-selection', '--filename=' + StartPath], Output, [poRunIdle]);
  if not Result then Exit;
  // The helpers append a newline to the selected path.
  if (Output <> '') and (Output[Length(Output)] = #10) then
    SetLength(Output, Length(Output) - 1);
  Selected := Output;
  Result := Path(Selected).IsAbsolute and Path(Selected).IsFile and
    (fpAccess(PChar(Selected), X_OK) = 0);
end;
{$ENDIF}

{$IF Defined(UNIX) and not Defined(DARWIN)}
procedure ExternalToolPathEntered(Value: boolean; Data: Pointer);
begin
  if not Value then Exit;
  Ini.ExternalSongEditorPath := Trim(ScreenPopupInsertUser.Username);
  Ini.Save;
end;

{$ENDIF}

procedure BrowseSongEditor;
var
  Selected: UTF8String;
  {$IF Defined(UNIX) and not Defined(DARWIN)}
  KDE: boolean;
  Picker: string;
  {$ENDIF}
begin
  {$IF Defined(WINDOWS) or Defined(DARWIN)}
  if not PickEditorFile(Selected) then Exit;
  {$ELSEIF Defined(UNIX)}
  KDE := Pos(':KDE:', ':' + UpperCase(GetEnvironmentVariable('XDG_CURRENT_DESKTOP')) + ':') > 0;
  Picker := FindEditorPicker(KDE);
  if Picker = '' then
  begin
    KDE := not KDE;
    Picker := FindEditorPicker(KDE);
  end;
  if Picker = '' then
  begin
    ScreenPopupInsertUser.ShowTextPrompt(Language.Translate('EXTERNAL_SONG_EDITOR_PATH'),
      'EXTERNAL_SONG_PATH_HINT', Language.Translate('FILTER_PRESET_SAVE'),
      @ExternalToolPathEntered, nil, Ini.ExternalSongEditorPath, 'EXTERNAL_SONG_PATH');
    Exit;
  end;
  try
    if not PickEditorFile(Picker, KDE, Selected) then Exit;
  except
    on E: Exception do
    begin
      Log.LogError(E.Message, 'External song editor picker');
      Exit;
    end;
  end;
  {$ELSE}
  Exit;
  {$ENDIF}
  Ini.ExternalSongEditorPath := Selected;
  Ini.Save;
end;

function TScreenOptionsAdvanced.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
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
            if Interactions[SelInteraction].Num = EditorPathButton then
            begin
              BrowseSongEditor;
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

  AddSection('EXTERNAL_SONG_TOOLS');
  AddSelectSlide('EXTERNAL_SONG_EDITOR', Ini.ExternalSongEditor,
    [Language.Translate('OPTION_VALUE_OFF'), IExternalSongEditor[1], IExternalSongEditor[2],
     Language.Translate('EXTERNAL_SONG_CUSTOM')]);
  EditorPathButton := AddButton('EXTERNAL_SONG_EDITOR_PATH');

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
