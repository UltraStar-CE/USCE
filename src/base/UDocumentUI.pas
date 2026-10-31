{ SPDX-License-Identifier: GPL-2.0-or-later }
unit UDocumentUI;
{$IFDEF FPC}{$MODE Delphi}{$ENDIF}
interface
uses Classes, SysUtils;
const
  uiKeyNext = 3;
  uiKeyPrevious = -3;
  uiScreenPartyOptions = 'party-options';
  uiScreenTournamentOptions = 'tournament-options';
  uiScreenTournamentPlayers = 'tournament-players';
  uiParticipantsPrevious = 'participants.previous';
  uiParticipantsNext = 'participants.next';
  uiParticipantsContinue = 'participants.continue';
  uiParticipantsSelect = 'participants.select';
  uiScreenPlayers = 'players';
  uiPlayersContinue = 'players.continue';
  uiPlayersPrevious = 'players.previous';
  uiPlayersNext = 'players.next';
  uiPlayersSelect = 'players.select';
  uiPlayersAvatarSelect = 'players.avatar.select';
  uiLoadingStatus = 'loading.status';
  uiLoadingDiscovery = 'loading.discovery';
  uiLoadingProgress = 'loading.progress';
  uiAboutText = 'about.text';
  uiGameVersion = 'game.version';
  uiGameSing = 'game.sing';
  uiGameParty = 'game.party';
  uiStatisticsOpen = 'statistics.open';
  uiScreenStatistics = 'statistics';
  uiStatisticsOverview = 'statistics.overview';
  uiStatisticsDetail = 'statistics.detail.open';
  uiStatisticsPeriod = 'statistics.period.next';
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
  uiFormChoose = 'form.choose';
  uiFormActivate = 'form.activate';
  uiScreenSettingsGame = 'settings-game';
  uiScreenSettingsGraphics = 'settings-graphics';
  uiFormPreview = 'form.preview';
  uiScreenSettingsRecording = 'settings-recording';
  uiScreenSettingsWebcam = 'settings-webcam';
  uiScreenSettingsLyrics = 'settings-lyrics';
  uiScreenSettingsSound = 'settings-sound';
  uiScreenSettingsInput = 'settings-input';
  uiScreenSettingsAdvanced = 'settings-advanced';
type
  TDocumentRegion = record
    X, Y, W, H: single;
  end;
  TDocumentUI = class
  private
    DocumentHandle: QWord;
    HandleGeneration: Cardinal;
    FileName, ArrayBinding: UTF8String;
    ColorStyle, SkinStyle: UTF8String;
    Values: TStringList;
    ValuesDirty: boolean;
    LastActionTarget: UTF8String;
    function Activate: boolean;
  public
    class function Open(const ScreenName: string; const ArrayBinding: UTF8String = ''): TDocumentUI;
    constructor Create(const AFileName: UTF8String);
    destructor Destroy; override;
    procedure SetValue(const Name, Value: UTF8String);
    procedure SetNumber(const Name: UTF8String; Value: double);
    function Draw(BackgroundOnly: boolean = false; ForegroundOnly: boolean = false): boolean;
    procedure PrepareLayout;
    procedure Mouse(X, Y: integer; Button: integer = -1; Down: boolean = false);
    procedure Key(Direction: integer);
    procedure Scroll(Delta: single);
    procedure ScrollTo(const ID: UTF8String; Position: Single);
    function ScrollPosition(const ID: UTF8String): Single;
    function Region(const ID: UTF8String; out Bounds: TDocumentRegion): boolean;
    function TakeAction: UTF8String;
    function FocusedTarget: UTF8String;
    procedure SetModel(const Name, Value: UTF8String; ValueType: integer = 0);
    procedure SetArray(const Name: UTF8String; Count: integer);
    procedure Focus(const ID: UTF8String);
    procedure Reveal(const ID: UTF8String);
    property ActionTarget: UTF8String read LastActionTarget;
  end;
procedure ShutdownDocumentUI;
implementation
uses DynLibs, IniFiles, ULanguage, ULog, UGraphic, UMenuBackground, UIni, URenderer;
type
  TTranslate = function(Key: PAnsiChar): PAnsiChar; cdecl;
  TLogger = procedure(Severity: integer; Message: PAnsiChar); cdecl;
var
  LibraryHandle: TLibHandle = NilHandle;
  Current: TDocumentUI;
  RuntimeGeneration: Cardinal;
  TranslationBuffer: UTF8String;
  Initialize: function(Translate: TTranslate; Logger: TLogger; Font, BoldFont: PAnsiChar): integer; cdecl;
  ApplyStyle: function(FileName: PAnsiChar): integer; cdecl;
  CreateDocument: function(FileName, ArrayBinding: PAnsiChar): QWord; cdecl;
  SelectDocument: function(Handle: QWord): integer; cdecl;
  DestroyDocument: procedure(Handle: QWord); cdecl;
  SetBinding: procedure(Name, Value: PAnsiChar); cdecl;
  Render: procedure(Width, Height, ForegroundOnly: integer); cdecl;
  Prepare: procedure(Width, Height: integer); cdecl;
  ProcessMouse: procedure(X, Y, Button, Down: integer); cdecl;
  ProcessKey: procedure(Direction: integer); cdecl;
  ProcessScroll: procedure(Delta: single); cdecl;
  SetScrollPosition: procedure(ID: PAnsiChar; Position: Single); cdecl;
  GetScrollPosition: function(ID: PAnsiChar): Single; cdecl;
  GetBounds: function(ID: PAnsiChar; out X, Y, W, H: single): integer; cdecl;
  GetAction: function: PAnsiChar; cdecl;
  GetActionTarget, GetFocusedTarget: function: PAnsiChar; cdecl;
  SetModelValue: procedure(Name, Value: PAnsiChar; ValueType: integer); cdecl;
  SetModelArray: procedure(Name: PAnsiChar; Count: integer); cdecl;
  FocusElement, RevealElement: procedure(ID: PAnsiChar); cdecl;
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
    @CreateDocument := Symbol('ui_create');
    @SelectDocument := Symbol('ui_select');
    @DestroyDocument := Symbol('ui_destroy');
    @ApplyStyle := Symbol('ui_style');
    @SetBinding := Symbol('ui_set');
    @Render := Symbol('ui_render');
    @Prepare := Symbol('ui_prepare');
    @ProcessMouse := Symbol('ui_mouse');
    @ProcessKey := Symbol('ui_key');
    @ProcessScroll := Symbol('ui_scroll');
    @SetScrollPosition := Symbol('ui_scroll_to');
    @GetScrollPosition := Symbol('ui_scroll_position');
    @GetBounds := Symbol('ui_bounds');
    @GetAction := Symbol('ui_action');
    @GetActionTarget := Symbol('ui_action_target');
    @GetFocusedTarget := Symbol('ui_focused_target');
    @SetModelValue := Symbol('ui_model_set');
    @SetModelArray := Symbol('ui_model_array');
    @FocusElement := Symbol('ui_focus');
    @RevealElement := Symbol('ui_reveal');
    @ClearAction := Symbol('ui_clear_action');
    @GetError := Symbol('ui_error');
    Result := Initialize(@TranslateKey, @FrontendLog, PAnsiChar(Font), PAnsiChar(BoldFont)) <> 0;
    if not Result then Log.LogWarn(UTF8String(GetError()), 'DocumentUI');
    if Result then
    begin
      Inc(RuntimeGeneration);
      Log.LogStatus('Loaded document frontend', 'DocumentUI');
    end;
  except
    on E: Exception do Log.LogWarn(E.Message, 'DocumentUI');
  end;
  if not Result then ShutdownDocumentUI;
end;

class function TDocumentUI.Open(const ScreenName: string; const ArrayBinding: UTF8String): TDocumentUI;
var Root, DocumentFile, Font, BoldFont, Style, SkinSheet, CompatibleTheme: UTF8String; Manifest: TMemIniFile;
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
    CompatibleTheme := Manifest.ReadString('Frontend', 'LegacyTheme', '');
    if (CompatibleTheme <> '') and ((Ini.Theme < 0) or (Ini.Theme >= Length(ITheme)) or
      not SameText(CompatibleTheme, ITheme[Ini.Theme])) then Exit;
    SkinSheet := '';
    if (Ini.SkinNo >= 0) and (Ini.SkinNo < Length(ISkin)) then
      SkinSheet := Manifest.ReadString('Styles', 'Skin.' + ISkin[Ini.SkinNo], '');
    if SkinSheet <> '' then SkinSheet := ExpandFileName(Root + SkinSheet);
    Style := '';
    if (Ini.Color >= Low(IColor)) and (Ini.Color <= High(IColor)) then
      Style := Manifest.ReadString('Styles', 'Color.' + IColor[Ini.Color], '');
    if Style <> '' then Style := ExpandFileName(Root + Style);
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
  Result := TDocumentUI.Create(DocumentFile);
  Result.ArrayBinding := ArrayBinding;
  Result.ColorStyle := Style;
  Result.SkinStyle := SkinSheet;
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
  if (LibraryHandle <> NilHandle) and (HandleGeneration = RuntimeGeneration) and
     (DocumentHandle <> 0) then DestroyDocument(DocumentHandle);
  Values.Free;
  inherited;
end;

function TDocumentUI.Activate: boolean;
var I: integer;
begin
  Result := LibraryHandle <> NilHandle;
  if not Result or (Current = Self) then Exit;
  Current := nil;
  if HandleGeneration <> RuntimeGeneration then DocumentHandle := 0;
  if DocumentHandle <> 0 then
  begin
    Result := SelectDocument(DocumentHandle) <> 0;
    if Result then
    begin
      Current := Self;
      if ValuesDirty then
        for I := 0 to Values.Count - 1 do
          SetBinding(PAnsiChar(UTF8String(Values.Names[I])), PAnsiChar(UTF8String(Values.ValueFromIndex[I])));
      ValuesDirty := false;
      Exit;
    end;
    DocumentHandle := 0;
  end;
  DocumentHandle := CreateDocument(PAnsiChar(FileName), PAnsiChar(ArrayBinding));
  Result := DocumentHandle <> 0;
  if not Result then begin Log.LogWarn(UTF8String(GetError()), 'DocumentUI'); Exit; end;
  HandleGeneration := RuntimeGeneration;
  if ((SkinStyle <> '') and (ApplyStyle(PAnsiChar(SkinStyle)) = 0)) or
     ((ColorStyle <> '') and (ApplyStyle(PAnsiChar(ColorStyle)) = 0)) then
  begin
    Log.LogWarn(UTF8String(GetError()), 'DocumentUI');
    DestroyDocument(DocumentHandle); DocumentHandle := 0;
    Exit(false);
  end;
  Current := Self;
  for I := 0 to Values.Count - 1 do
    SetBinding(PAnsiChar(UTF8String(Values.Names[I])), PAnsiChar(UTF8String(Values.ValueFromIndex[I])));
  ValuesDirty := false;
end;

procedure TDocumentUI.PrepareLayout;
begin
  if Activate then Prepare(ScreenW, ScreenH);
end;

procedure TDocumentUI.SetValue(const Name, Value: UTF8String);
var Index: integer;
begin
  Index := Values.IndexOfName(Name);
  if (Index >= 0) and (Values.ValueFromIndex[Index] = Value) then Exit;
  // Preserve empty entries too: an inactive document may need old text cleared.
  if Index < 0 then Values.Add(Name + '=' + Value)
  else Values.Strings[Index] := Name + '=' + Value;
  if Current = Self then SetBinding(PAnsiChar(Name), PAnsiChar(Value))
  else ValuesDirty := true;
end;

function TDocumentUI.Draw(BackgroundOnly, ForegroundOnly: boolean): boolean;
begin
  if BackgroundOnly and TMenuBackground.SuppressDrawing then Exit(true);
  Result := Activate;
  if Result then
  begin
    if not ForegroundOnly and not TMenuBackground.SuppressDrawing then
      Renderer.ClearFrameBuffer(CLEAR_DEPTH);
    if BackgroundOnly then Render(ScreenW, ScreenH, 2)
    else Render(ScreenW, ScreenH, Ord(ForegroundOnly or TMenuBackground.SuppressDrawing));
  end;
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

function TDocumentUI.Region(const ID: UTF8String; out Bounds: TDocumentRegion): boolean;
begin
  FillChar(Bounds, SizeOf(Bounds), 0);
  Result := Activate and (GetBounds(PAnsiChar(ID), Bounds.X, Bounds.Y, Bounds.W, Bounds.H) <> 0);
  if Result then
  begin
    Bounds.X := Bounds.X * RenderW / ScreenW;
    Bounds.Y := Bounds.Y * RenderH / ScreenH;
    Bounds.W := Bounds.W * RenderW / ScreenW;
    Bounds.H := Bounds.H * RenderH / ScreenH;
  end;
end;

procedure TDocumentUI.ScrollTo(const ID: UTF8String; Position: Single);
begin
  if Activate then
  begin
    Prepare(ScreenW, ScreenH);
    SetScrollPosition(PAnsiChar(ID), Position);
  end;
end;

function TDocumentUI.ScrollPosition(const ID: UTF8String): Single;
begin
  Result := 0;
  if Activate then
  begin
    Prepare(ScreenW, ScreenH);
    Result := GetScrollPosition(PAnsiChar(ID));
  end;
end;

procedure TDocumentUI.Scroll(Delta: single);
begin
  if Activate then ProcessScroll(Delta);
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

procedure TDocumentUI.Reveal(const ID: UTF8String);
begin
  if Activate then RevealElement(PAnsiChar(ID));
end;

procedure TDocumentUI.Focus(const ID: UTF8String);
begin
  if Activate then FocusElement(PAnsiChar(ID));
end;
end.
