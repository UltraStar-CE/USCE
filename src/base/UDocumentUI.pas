{ SPDX-License-Identifier: GPL-2.0-or-later }
unit UDocumentUI;
{$IFDEF FPC}{$MODE Delphi}{$ENDIF}
interface
uses Classes, SysUtils;
const
  uiLoadingStatus = 'loading.status';
  uiLoadingDiscovery = 'loading.discovery';
  uiLoadingProgress = 'loading.progress';
  uiGameVersion = 'game.version';
  uiGameSing = 'game.sing';
  uiGameParty = 'game.party';
  uiStatisticsOpen = 'statistics.open';
  uiSettingsOpen = 'settings.open';
  uiAboutOpen = 'about.open';
  uiCreditsOpen = 'credits.open';
  uiGameExit = 'game.exit';
  uiSettingsGame = 'settings.game.open';
  uiSettingsGraphics = 'settings.graphics.open';
  uiSettingsSound = 'settings.sound.open';
  uiSettingsInput = 'settings.input.open';
  uiSettingsLyrics = 'settings.lyrics.open';
  uiSettingsThemes = 'settings.themes.open';
  uiSettingsRecording = 'settings.recording.open';
  uiSettingsAdvanced = 'settings.advanced.open';
  uiSettingsNetwork = 'settings.network.open';
  uiSettingsWebcam = 'settings.webcam.open';
  uiNavigationBack = 'navigation.back';
  uiFormFields = 'form.fields';
  uiFormDescription = 'form.description';
  uiFormWhereAmI = 'form.whereami';
  uiFormIncrement = 'form.increment';
  uiFormDecrement = 'form.decrement';
  uiFormActivate = 'form.activate';
  uiScreenSettingsGame = 'settings-game';
  uiScreenSettingsGraphics = 'settings-graphics';
  uiScreenSettingsInput = 'settings-input';
  uiScreenSettingsAdvanced = 'settings-advanced';
type
  TDocumentUI = class
  private
    FileName: UTF8String;
    Values: TStringList;
    LastActionTarget: UTF8String;
    function Activate: boolean;
  public
    class function Open(const ScreenName: string; const ArrayBinding: UTF8String = ''): TDocumentUI;
    constructor Create(const AFileName: UTF8String);
    destructor Destroy; override;
    procedure SetValue(const Name, Value: UTF8String);
    procedure SetNumber(const Name: UTF8String; Value: double);
    function Draw(BackgroundOnly: boolean = false): boolean;
    procedure Mouse(X, Y: integer; Button: integer = -1; Down: boolean = false);
    procedure Key(Direction: integer);
    function TakeAction: UTF8String;
    function FocusedTarget: UTF8String;
    procedure SetModel(const Name, Value: UTF8String; ValueType: integer = 0);
    procedure SetArray(const Name: UTF8String; Count: integer);
    procedure Focus(const ID: UTF8String);
    property ActionTarget: UTF8String read LastActionTarget;
  end;
procedure ShutdownDocumentUI;
implementation
uses DynLibs, IniFiles, ULanguage, ULog, UGraphic, UMenuBackground;
type
  TTranslate = function(Key: PAnsiChar): PAnsiChar; cdecl;
  TLogger = procedure(Severity: integer; Message: PAnsiChar); cdecl;
var
  LibraryHandle: TLibHandle = NilHandle;
  Current: TDocumentUI;
  TranslationBuffer: UTF8String;
  Initialize: function(Translate: TTranslate; Logger: TLogger; Font, BoldFont: PAnsiChar): integer; cdecl;
  OpenDocument: function(FileName: PAnsiChar): integer; cdecl;
  SetBinding: procedure(Name, Value: PAnsiChar); cdecl;
  Render: procedure(Width, Height, ForegroundOnly: integer); cdecl;
  ProcessMouse: procedure(X, Y, Button, Down: integer); cdecl;
  ProcessKey: procedure(Direction: integer); cdecl;
  GetAction: function: PAnsiChar; cdecl;
  GetActionTarget, GetFocusedTarget: function: PAnsiChar; cdecl;
  SetModelValue: procedure(Name, Value: PAnsiChar; ValueType: integer); cdecl;
  SetModelArray: procedure(Name: PAnsiChar; Count: integer); cdecl;
  FocusElement: procedure(ID: PAnsiChar); cdecl;
  ClearAction, Shutdown: procedure; cdecl;
  GetError: function: PAnsiChar; cdecl;

function TranslateKey(Key: PAnsiChar): PAnsiChar; cdecl;
begin
  TranslationBuffer := Language.Translate(UTF8String(Key));
  Result := PAnsiChar(TranslationBuffer);
end;

procedure FrontendLog(Severity: integer; Message: PAnsiChar); cdecl;
begin
  if Severity <= 3 then Log.LogWarn(UTF8String(Message), 'DocumentUI')
  else Log.LogDebug(UTF8String(Message), 'DocumentUI');
end;

procedure ShutdownDocumentUI;
begin
  Current := nil;
  if LibraryHandle = NilHandle then Exit;
  if Assigned(Shutdown) then Shutdown();
  UnloadLibrary(LibraryHandle);
  LibraryHandle := NilHandle;
  Shutdown := nil;
end;

function LoadRuntime(const Font, BoldFont: UTF8String): boolean;
  function Symbol(const Name: AnsiString): Pointer;
  begin
    Result := GetProcedureAddress(LibraryHandle, PAnsiChar(Name));
    if Result = nil then raise Exception.Create('Missing document UI symbol: ' + Name);
  end;
begin
  if LibraryHandle <> NilHandle then Exit(true);
  Result := false;
  LibraryHandle := LoadLibrary(ExtractFilePath(ParamStr(0)) +
    {$IFDEF MSWINDOWS}'usce-document-ui.dll'{$ELSE}{$IFDEF DARWIN}'usce-document-ui.dylib'{$ELSE}'usce-document-ui.so'{$ENDIF}{$ENDIF});
  if LibraryHandle = NilHandle then Exit;
  try
    @Initialize := Symbol('ui_initialize');
    @Shutdown := Symbol('ui_shutdown');
    @OpenDocument := Symbol('ui_open');
    @SetBinding := Symbol('ui_set');
    @Render := Symbol('ui_render');
    @ProcessMouse := Symbol('ui_mouse');
    @ProcessKey := Symbol('ui_key');
    @GetAction := Symbol('ui_action');
    @GetActionTarget := Symbol('ui_action_target');
    @GetFocusedTarget := Symbol('ui_focused_target');
    @SetModelValue := Symbol('ui_model_set');
    @SetModelArray := Symbol('ui_model_array');
    @FocusElement := Symbol('ui_focus');
    @ClearAction := Symbol('ui_clear_action');
    @GetError := Symbol('ui_error');
    Result := Initialize(@TranslateKey, @FrontendLog, PAnsiChar(Font), PAnsiChar(BoldFont)) <> 0;
    if not Result then Log.LogWarn(UTF8String(GetError()), 'DocumentUI');
    if Result then Log.LogStatus('Loaded document frontend', 'DocumentUI');
  except
    on E: Exception do Log.LogWarn(E.Message, 'DocumentUI');
  end;
  if not Result then ShutdownDocumentUI;
end;

class function TDocumentUI.Open(const ScreenName: string; const ArrayBinding: UTF8String): TDocumentUI;
var Root, DocumentFile, Font, BoldFont: UTF8String; Manifest: TMemIniFile;
begin
  Result := nil;
  if Screens <> 1 then Exit;
  Root := GetEnvironmentVariable('USCE_FRONTEND');
  if Root = '' then Exit;
  Root := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  if not FileExists(Root + 'frontend.ini') then Exit;
  Manifest := TMemIniFile.Create(Root + 'frontend.ini');
  try
    if Manifest.ReadInteger('Frontend', 'API', 0) <> 1 then Exit;
    DocumentFile := Manifest.ReadString('Screens', ScreenName, '');
    if DocumentFile = '' then Exit;
    DocumentFile := ExpandFileName(Root + DocumentFile);
    Font := ExpandFileName(Root + Manifest.ReadString('Frontend', 'Font', ''));
    BoldFont := Manifest.ReadString('Frontend', 'BoldFont', '');
    if BoldFont <> '' then BoldFont := ExpandFileName(Root + BoldFont);
  finally
    Manifest.Free;
  end;
  if not FileExists(DocumentFile) or not LoadRuntime(Font, BoldFont) then Exit;
  if ArrayBinding <> '' then SetModelArray(PAnsiChar(ArrayBinding), 0);
  Result := TDocumentUI.Create(DocumentFile);
  if not Result.Activate then FreeAndNil(Result);
end;

constructor TDocumentUI.Create(const AFileName: UTF8String);
begin
  inherited Create;
  FileName := AFileName;
  Values := TStringList.Create;
end;

destructor TDocumentUI.Destroy;
begin
  if Current = Self then Current := nil;
  Values.Free;
  inherited;
end;

function TDocumentUI.Activate: boolean;
var I: integer;
begin
  Result := LibraryHandle <> NilHandle;
  if not Result or (Current = Self) then Exit;
  Current := nil;
  Result := OpenDocument(PAnsiChar(FileName)) <> 0;
  if not Result then begin Log.LogWarn(UTF8String(GetError()), 'DocumentUI'); Exit; end;
  Current := Self;
  for I := 0 to Values.Count - 1 do
    SetBinding(PAnsiChar(UTF8String(Values.Names[I])), PAnsiChar(UTF8String(Values.ValueFromIndex[I])));
end;

procedure TDocumentUI.SetValue(const Name, Value: UTF8String);
begin
  if Values.Values[Name] = Value then Exit;
  Values.Values[Name] := Value;
  if Current = Self then SetBinding(PAnsiChar(Name), PAnsiChar(Value));
end;

function TDocumentUI.Draw(BackgroundOnly: boolean): boolean;
begin
  Result := Activate;
  if Result then
    if BackgroundOnly then Render(ScreenW, ScreenH, 2)
    else Render(ScreenW, ScreenH, Ord(TMenuBackground.SuppressDrawing));
end;

procedure TDocumentUI.SetNumber(const Name: UTF8String; Value: double);
var NumberFormat: TFormatSettings;
begin
  NumberFormat := DefaultFormatSettings;
  NumberFormat.DecimalSeparator := '.';
  SetValue(Name, FloatToStr(Value, NumberFormat));
end;

procedure TDocumentUI.Mouse(X, Y, Button: integer; Down: boolean);
begin
  if Activate then ProcessMouse(X, Y, Button, Ord(Down));
end;

procedure TDocumentUI.Key(Direction: integer);
begin
  if Activate then ProcessKey(Direction);
end;

function TDocumentUI.TakeAction: UTF8String;
begin
  Result := '';
  if not Activate then Exit;
  Result := UTF8String(GetAction());
  LastActionTarget := UTF8String(GetActionTarget());
  ClearAction();
end;

function TDocumentUI.FocusedTarget: UTF8String;
begin
  Result := '';
  if Current = Self then Result := UTF8String(GetFocusedTarget());
end;

procedure TDocumentUI.SetModel(const Name, Value: UTF8String; ValueType: integer);
begin
  if Activate then SetModelValue(PAnsiChar(Name), PAnsiChar(Value), ValueType);
end;

procedure TDocumentUI.SetArray(const Name: UTF8String; Count: integer);
begin
  if Activate then SetModelArray(PAnsiChar(Name), Count);
end;

procedure TDocumentUI.Focus(const ID: UTF8String);
begin
  if Activate then FocusElement(PAnsiChar(ID));
end;
end.
