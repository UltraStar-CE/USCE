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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenStatDetail.pas $
 * $Id: UScreenStatDetail.pas 1972 2009-12-06 12:13:34Z s_alexander $
 *}

unit UScreenStatDetail;

interface

{$IFDEF FPC}
  {$mode objfpc}//{$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDataBase,
  UDisplay,
  UDocumentUI,
  UIni,
  UMenu,
  UMenuList,
  UMusic,
  UThemes,
  sdl2,
  SysUtils,
  Classes;

type
  TStatDetailCellValue = (
    scvNone,
    scvRank,
    scvScore,
    scvPlayer,
    scvDifficulty,
    scvDate,
    scvSong,
    scvAverageScore,
    scvSingCount,
    scvArtist
  );

  TScreenStatDetail = class(TMenu)
    private
      DocumentUI: TDocumentUI;
      TextHeader: array[0..STAT_DETAIL_MAX_COLUMNS - 1] of integer;
      TextHeaderRight: array[0..STAT_DETAIL_MAX_COLUMNS - 1] of integer;
      RowsPerColumn: integer;
      TextList: array of array of integer;
      ListColumns: array[0..STAT_DETAIL_MAX_COLUMNS - 1] of TListColumn;
      TextListValue: array[0..STAT_DETAIL_MAX_COLUMNS - 1] of TStatDetailCellValue;
      TextDescription: integer;
      TextPage: integer;
      StaticMinMedian: integer;
      TextMinMedian: integer;
      EntriesPerPage: integer;
      MinMedianFilter: boolean;

      procedure SetDocumentPage(StatList: TList; VisibleEntries: integer; const PageText: UTF8String);
      function DocumentAction(const Action: UTF8String): boolean;

      procedure ChangeEntriesPerPage(Delta: integer);
      procedure ClearRows;
      procedure RecalculatePages;
      procedure SetRowText(Row, Column: integer; const Value: UTF8String);
      function StatCellText(StatList: TList; Row: integer; Value: TStatDetailCellValue): UTF8String;
      procedure UpdateListLayout(StatList: TList; VisibleEntries: integer);
      procedure ToggleMinMedianFilter;
      procedure UpdateMinMedianHint;
      function ActiveFilters: TStatFilters;

    public
      Typ:  TStatType;
      Page: cardinal;

      TotEntrys: cardinal;
      TotPages:  cardinal;

      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      procedure OnWindowResized; override;

      procedure SetTitle;
      procedure SetPage(NewPage: cardinal);
  end;

const
  uiStatDetailRole = 'statistics-detail';
  uiStatDetailData = 'statisticsDetail';
  uiStatPreviousPage = 'statistics.page.previous';
  uiStatNextPage = 'statistics.page.next';
  uiStatFewerEntries = 'statistics.entries.fewer';
  uiStatMoreEntries = 'statistics.entries.more';
  uiStatCyclePeriod = 'statistics.period.next';
  uiStatMedianFilter = 'statistics.median.toggle';
  ID='ID_051';   //for help system

implementation

uses
  UCommon,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UText,
  UStatistics,
  UUnicodeUtils,
  Math,
  StrUtils;

type
  TStatDetailColumnDefinition = record
    Header: RawByteString;
    Value: TStatDetailCellValue;
  end;

  TStatDetailColumnDefinitions = array[0..STAT_DETAIL_MAX_COLUMNS - 1] of TStatDetailColumnDefinition;


const
  BEST_SCORE_COLUMNS: TStatDetailColumnDefinitions = (
    (Header: 'STAT_DETAIL_HEADER_RANK';       Value: scvRank),
    (Header: 'STAT_DETAIL_HEADER_SCORE';      Value: scvScore),
    (Header: 'STAT_DETAIL_HEADER_PLAYER';     Value: scvPlayer),
    (Header: 'STAT_DETAIL_HEADER_DIFFICULTY'; Value: scvDifficulty),
    (Header: 'STAT_DETAIL_HEADER_DATE';       Value: scvDate),
    (Header: 'STAT_DETAIL_HEADER_SONG';       Value: scvSong)
  );
  BEST_SINGER_COLUMNS: TStatDetailColumnDefinitions = (
    (Header: 'STAT_DETAIL_HEADER_RANK';      Value: scvRank),
    (Header: 'STAT_DETAIL_HEADER_PLAYER';    Value: scvPlayer),
    (Header: 'STAT_DETAIL_HEADER_AVG_SCORE'; Value: scvAverageScore),
    (Header: 'STAT_DETAIL_HEADER_SCORES';    Value: scvSingCount),
    (Header: '';                             Value: scvNone),
    (Header: '';                             Value: scvNone)
  );
  POPULAR_SONG_COLUMNS: TStatDetailColumnDefinitions = (
    (Header: 'STAT_DETAIL_HEADER_RANK';      Value: scvRank),
    (Header: 'STAT_DETAIL_HEADER_SONG';      Value: scvSong),
    (Header: 'STAT_DETAIL_HEADER_SUNG';      Value: scvSingCount),
    (Header: 'STAT_DETAIL_HEADER_AVG_SCORE'; Value: scvAverageScore),
    (Header: '';                             Value: scvNone),
    (Header: '';                             Value: scvNone)
  );
  POPULAR_BAND_COLUMNS: TStatDetailColumnDefinitions = (
    (Header: 'STAT_DETAIL_HEADER_RANK';      Value: scvRank),
    (Header: 'STAT_DETAIL_HEADER_ARTIST';    Value: scvArtist),
    (Header: 'STAT_DETAIL_HEADER_SUNG';      Value: scvSingCount),
    (Header: 'STAT_DETAIL_HEADER_AVG_SCORE'; Value: scvAverageScore),
    (Header: '';                             Value: scvNone),
    (Header: '';                             Value: scvNone)
  );

function FormatStatSong(const Artist, Title: UTF8String): UTF8String;
begin
  if (Artist = '') then
    Result := Title
  else if (Title = '') then
    Result := Artist
  else
    Result := Artist + ' - ' + Title;
end;

function FormatStatCount(Count: integer): UTF8String;
begin
  Result := IntToStr(Count);
end;

function TScreenStatDetail.DocumentAction(const Action: UTF8String): boolean;
begin
  Result := true;
  if Action = uiNavigationBack then Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if Action = uiStatPreviousPage then Exit(ParseInput(SDLK_LEFT, 0, true));
  if Action = uiStatNextPage then Exit(ParseInput(SDLK_RIGHT, 0, true));
  if Action = uiStatFewerEntries then Exit(ParseInput(SDLK_UP, 0, true));
  if Action = uiStatMoreEntries then Exit(ParseInput(SDLK_DOWN, 0, true));
  if Action = uiStatCyclePeriod then Exit(ParseInput(SDLK_T, 0, true));
  if Action = uiStatMedianFilter then Exit(ParseInput(SDLK_M, 0, true));
end;

function TScreenStatDetail.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
begin
  if DocumentUI = nil then Exit(inherited);
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown) else DocumentUI.Mouse(X, Y);
  if BtnDown and (MouseButton = SDL_BUTTON_WHEELUP) then Exit(ParseInput(SDLK_UP, 0, true));
  if BtnDown and (MouseButton = SDL_BUTTON_WHEELDOWN) then Exit(ParseInput(SDLK_DOWN, 0, true));
  Result := DocumentAction(DocumentUI.TakeAction);
end;

destructor TScreenStatDetail.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenStatDetail.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenStatDetail.DrawFG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(false, true) else Result := inherited;
end;

procedure TScreenStatDetail.SetDocumentPage(StatList: TList; VisibleEntries: integer; const PageText: UTF8String);
const
  Titles: array[TStatType] of UTF8String = ('STAT_DESC_SCORES', 'STAT_DESC_SINGERS', 'STAT_DESC_SONGS', 'STAT_DESC_BANDS');
var
  Definitions: TStatDetailColumnDefinitions;
  Column, Row, Count: integer;
  Prefix, CellPrefix, Header: UTF8String;
begin
  case Typ of
    stBestScores: Definitions := BEST_SCORE_COLUMNS;
    stBestSingers: Definitions := BEST_SINGER_COLUMNS;
    stMostSungSong: Definitions := POPULAR_SONG_COLUMNS;
    stMostPopBand: Definitions := POPULAR_BAND_COLUMNS;
  end;
  Count := Length(Definitions);
  while (Count > 0) and (Definitions[Count - 1].Value = scvNone) do Dec(Count);
  DocumentUI.SetModel(uiStatDetailData + '.kind', IntToStr(Ord(Typ)), 1);
  DocumentUI.SetModel(uiStatDetailData + '.pageSize', IntToStr(EntriesPerPage), 1);
  DocumentUI.SetModel(uiStatDetailData + '.previousPage', IntToStr(Ord(Page > 0)), 2);
  DocumentUI.SetModel(uiStatDetailData + '.nextPage', IntToStr(Ord(Page + 1 < TotPages)), 2);
  DocumentUI.SetModel(uiStatDetailData + '.medianAvailable', IntToStr(Ord(Typ = stBestSingers)), 2);
  DocumentUI.SetModel(uiStatDetailData + '.medianActive', IntToStr(Ord(MinMedianFilter)), 2);
  DocumentUI.SetValue(uiStatDetailData + '.description', Language.Translate(Titles[Typ]) + ' - ' + StatPeriodText);
  DocumentUI.SetValue(uiStatDetailData + '.page', PageText);
  DocumentUI.SetArray(uiStatDetailData + '.columns', Count);
  for Column := 0 to Count - 1 do
  begin
    Prefix := uiStatDetailData + '.columns[' + IntToStr(Column) + '].';
    Header := Definitions[Column].Header;
    if (StatSinceDate > 0) and (Header = 'STAT_DETAIL_HEADER_SUNG') then Header := 'STAT_DETAIL_HEADER_SCORES';
    DocumentUI.SetModel(Prefix + 'id', IntToStr(Column), 1);
    DocumentUI.SetModel(Prefix + 'header', Language.Translate(Header));
    DocumentUI.SetModel(Prefix + 'numeric', IntToStr(Ord(Definitions[Column].Value in [scvRank, scvScore, scvAverageScore, scvSingCount])), 2);
    DocumentUI.SetModel(Prefix + 'flexible', IntToStr(Ord(Definitions[Column].Value in [scvPlayer, scvSong, scvArtist])), 2);
  end;
  DocumentUI.SetArray(uiStatDetailData + '.rows', VisibleEntries);
  for Row := 0 to VisibleEntries - 1 do
  begin
    Prefix := uiStatDetailData + '.rows[' + IntToStr(Row) + '].';
    DocumentUI.SetArray(Prefix + 'cells', Count);
    for Column := 0 to Count - 1 do
    begin
      CellPrefix := Prefix + 'cells[' + IntToStr(Column) + '].';
      DocumentUI.SetModel(CellPrefix + 'id', IntToStr(Column), 1);
      DocumentUI.SetModel(CellPrefix + 'value', StatCellText(StatList, Row, Definitions[Column].Value));
      DocumentUI.SetModel(CellPrefix + 'numeric', IntToStr(Ord(Definitions[Column].Value in [scvRank, scvScore, scvAverageScore, scvSingCount])), 2);
    end;
  end;
end;

function TScreenStatDetail.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
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
          AudioPlayback.PlaySound(SoundLib.Back);
          FadeTo(@ScreenStatMain);
        end;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_LEFT:
        begin
          if (Page > 0) then
            SetPage(Page - 1);
        end;
      SDLK_RIGHT:
        begin
          if (Page + 1 < TotPages) then
            SetPage(Page + 1);
        end;
      SDLK_UP:
        begin
          ChangeEntriesPerPage(-1);
        end;
      SDLK_DOWN:
        begin
          ChangeEntriesPerPage(1);
        end;
      SDLK_T:
        begin
          CycleStatPeriod;
          TotEntrys := DataBase.GetTotalEntrys(Typ, ActiveFilters, StatSinceDate);
          RecalculatePages;
          SetPage(0);
        end;
      SDLK_M:
        begin
          ToggleMinMedianFilter;
        end;
    end;
  end;
end;

constructor TScreenStatDetail.Create;
var
  Column: integer;
  Row: integer;
begin
  inherited Create;

  EntriesPerPage := EnsureRange(Ini.StatDetailCount, Theme.StatDetail.MinEntries, Theme.StatDetail.MaxEntries);
  if Ini.StatDetailCount <= 0 then EntriesPerPage := Theme.StatDetail.DefaultEntries;
  MinMedianFilter := false;
  Typ := TStatType(0);
  DocumentUI := TDocumentUI.Open(uiStatDetailRole);
  if DocumentUI <> nil then Exit;

  SetLength(TextList, Theme.StatDetail.MaxEntries, STAT_DETAIL_MAX_COLUMNS);

  for Row := 0 to High(TextList) do
    for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
      TextList[Row, Column] := AddText(Theme.StatDetail.TextList[0]);

  for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
  begin
    TextHeader[Column] := AddText(Theme.StatDetail.TextHeader);
    TextHeaderRight[Column] := AddText(Theme.StatDetail.TextHeader);
  end;

  TextDescription := AddText(Theme.StatDetail.TextDescription);
  TextPage := AddText(Theme.StatDetail.TextPage);

  LoadFromTheme(Theme.StatDetail);

  StaticMinMedian := AddStatic(Theme.StatDetail.StaticMinMedian);
  TextMinMedian := AddText(Theme.StatDetail.TextMinMedian);

  EntriesPerPage := EnsureRange(Ini.StatDetailCount,
      Theme.StatDetail.MinEntries, Theme.StatDetail.MaxEntries);
  if (Ini.StatDetailCount <= 0) then
    EntriesPerPage := Theme.StatDetail.DefaultEntries;
  MinMedianFilter := false;
  Typ := TStatType(0);
end;

procedure TScreenStatDetail.OnShow;
begin
  if DocumentUI = nil then inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenStatDetail');

  MinMedianFilter := false;

  //Set Tot Entrys and Pages
  TotEntrys := DataBase.GetTotalEntrys(Typ, ActiveFilters, StatSinceDate);
  RecalculatePages;
  UpdateMinMedianHint;

  //Show correct Title
  SetTitle;

  //Show First Page
  SetPage(0);
end;

procedure TScreenStatDetail.OnWindowResized;
begin
  inherited;
  SetPage(Page);
end;

procedure TScreenStatDetail.SetTitle;
begin
  if DocumentUI <> nil then Exit;
  Text[TextDescription].Text := Theme.StatDetail.Description[Ord(Typ)] +
      ' - ' + StatPeriodText;
end;

procedure TScreenStatDetail.RecalculatePages;
begin
  TotPages := Ceil(TotEntrys / EntriesPerPage);
  if TotPages = 0 then
    TotPages := 1;
end;

function TScreenStatDetail.ActiveFilters: TStatFilters;
begin
  Result := [];
  if (Typ = stBestSingers) and MinMedianFilter then
    Include(Result, sfMinMedianScoreCount);
end;

procedure TScreenStatDetail.UpdateMinMedianHint;
var
  ShowHint: boolean;
begin
  if DocumentUI <> nil then Exit;
  ShowHint := (Typ = stBestSingers);
  Statics[StaticMinMedian].Visible := ShowHint;
  Text[TextMinMedian].Visible := ShowHint;
end;

procedure TScreenStatDetail.ClearRows;
var
  Column: integer;
  Row: integer;
begin
  for Row := 0 to High(TextList) do
    for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
      Text[TextList[Row, Column]].Text := '';
end;

procedure TScreenStatDetail.SetRowText(Row, Column: integer; const Value: UTF8String);
var
  TextID: integer;
begin
  TextID := TextList[Row, Column];
  if ListColumns[Column].Width > 0 then
    SetListCellText(Text[TextID], ListColumns[Column], Value)
  else
    Text[TextID].Text := '';
end;

function TScreenStatDetail.StatCellText(StatList: TList; Row: integer;
    Value: TStatDetailCellValue): UTF8String;
begin
  Result := '';
  if (StatList = nil) or (Row < 0) or (Row >= StatList.Count) then
    Exit;

  case Typ of
    stBestScores:
      with TStatResultBestScores(StatList[Row]) do
      begin
        if (Score <= 0) then
          Exit;

        case Value of
          scvRank:       Result := IntToStr(Page * EntriesPerPage + Row + 1);
          scvScore:      Result := IntToStr(Score);
          scvPlayer:     Result := Singer;
          scvDifficulty: Result := Theme.ILevel[Difficulty];
          scvDate:       Result := Date;
          scvSong:       Result := FormatStatSong(SongArtist, SongTitle);
        end;
      end;

    stBestSingers:
      with TStatResultBestSingers(StatList[Row]) do
      begin
        if (AverageScore <= 0) then
          Exit;

        case Value of
          scvRank:         Result := IntToStr(Page * EntriesPerPage + Row + 1);
          scvPlayer:       Result := Player;
          scvAverageScore: Result := IntToStr(AverageScore);
          scvSingCount:    Result := FormatStatCount(Count);
        end;
      end;

    stMostSungSong:
      with TStatResultMostSungSong(StatList[Row]) do
      begin
        if (Artist = '') then
          Exit;

        case Value of
          scvRank:         Result := IntToStr(Page * EntriesPerPage + Row + 1);
          scvSong:         Result := FormatStatSong(Artist, Title);
          scvSingCount:    Result := FormatStatCount(TimesSung);
          scvAverageScore: Result := IntToStr(AverageScore);
        end;
      end;

    stMostPopBand:
      with TStatResultMostPopBand(StatList[Row]) do
      begin
        if (ArtistName = '') then
          Exit;

        case Value of
          scvRank:         Result := IntToStr(Page * EntriesPerPage + Row + 1);
          scvArtist:       Result := ArtistName;
          scvSingCount:    Result := FormatStatCount(TimesSungtot);
          scvAverageScore: Result := IntToStr(AverageScore);
        end;
      end;
  end;
end;

procedure TScreenStatDetail.UpdateListLayout(StatList: TList; VisibleEntries: integer);
var
  Column: integer;
  Row: integer;
  HeaderY: real;
  TopY: real;
  BottomY: real;
  ListLayout: TTextListLayout;
  HeaderSize: real;
  MaxTextSize: real;
  ListX: integer;
  ListY: integer;
  ListW: integer;
  ListBottomY: real;
  ColumnCompactFactor: real;
  ColumnOffset: real;
  LayoutRows: integer;
  ThemeText: TThemeText;

  function HeaderID(const TextID: RawByteString): RawByteString;
  begin
    Result := TextID;
    if (StatSinceDate > 0) and (TextID = 'STAT_DETAIL_HEADER_SUNG') then
      Result := 'STAT_DETAIL_HEADER_SCORES';
  end;

  procedure SetColumn(Column: integer; const Layout: TListColumn;
      const HeaderText: RawByteString);
  var
    TextID, Row: integer;
  begin
    TextID := TextHeader[Column];
    PositionListColumnText(Text[TextID], Layout);
    Text[TextID].W := 0;
    Text[TextID].H := 0;
    Text[TextID].Y := HeaderY;
    Text[TextID].Visible := Layout.Width > 0;
    SetListCellText(Text[TextID], Layout, Language.Translate(HeaderID(HeaderText)));
    TextID := TextHeaderRight[Column];
    PositionListColumnText(Text[TextID], Layout);
    Text[TextID].X := Text[TextID].X + ColumnOffset;
    Text[TextID].Y := HeaderY;
    Text[TextID].W := 0;
    Text[TextID].H := 0;
    Text[TextID].Visible := (ColumnOffset > 0) and (Layout.Width > 0);
    SetListCellText(Text[TextID], Layout, Language.Translate(HeaderID(HeaderText)));
    for Row := 0 to High(TextList) do
    begin
      TextID := TextList[Row, Column];
      PositionListColumnText(Text[TextID], Layout);
      if Row >= RowsPerColumn then
        Text[TextID].X := Text[TextID].X + ColumnOffset;
      Text[TextID].W := 0;
      Text[TextID].H := 0;
      Text[TextID].Visible := (Row < EntriesPerPage) and (Layout.Width > 0);
    end;
  end;

  function TableRightBound(const Table: TThemeStatDetailTable): real;
  begin
    Result := 1.0;

    if (ThemeText.W > 0) then
      Result := EnsureRange(Result - Table.RightInset /
          ThemeText.W, 0.0, 1.0);
  end;

  function TextWidthFactor(const Value: UTF8String; Font, Style: integer;
      Size, Padding: real): real;
  begin
    Result := 0;
    if (ThemeText.W > 0) and (Value <> '') then
      Result := (MeasureTextMaxLineWidth(Value, Font, Style, Size) + Padding) /
          ThemeText.W;
  end;

  function ValueColumnWidth(const HeaderText: RawByteString;
      Value: TStatDetailCellValue): real;
  var
    Row: integer;
    ValueText: UTF8String;
  begin
    Result := TextWidthFactor(Language.Translate(HeaderID(HeaderText)), ThemeText.Font,
        Theme.StatDetail.TextHeader.Style, HeaderSize, Theme.StatDetail.ColumnPadding);

    for Row := 0 to VisibleEntries - 1 do
    begin
      ValueText := StatCellText(StatList, Row, Value);
      if (ValueText <> '') then
        Result := Max(Result, TextWidthFactor(ValueText, ThemeText.Font,
            ThemeText.Style, ListLayout.TextSize, Theme.StatDetail.ColumnPadding));
    end;
  end;

  procedure SetColumns(const Table: TThemeStatDetailTable;
      const Definitions: TStatDetailColumnDefinitions);
  var
    Specs: array of TListColumnSpec;
    Column, ColumnCount, TrialRows: integer;
    FullWidth, RequiredWidth, Gap, RightBound: real;
    SingleLayout: TTextListLayout;
  begin
    ColumnCount := EnsureRange(Table.ColumnCount, 0, STAT_DETAIL_MAX_COLUMNS);
    while (ColumnCount > 0) and (Definitions[ColumnCount - 1].Value = scvNone) do
      Dec(ColumnCount);
    // Try two complete tables at the font size appropriate for half the rows.
    // Measure headers and values too; never force a second table by squeezing
    // out a score, date or song column.
    FullWidth := ThemeText.W;
    RightBound := TableRightBound(Table);
    SingleLayout := ListLayout;
    TrialRows := (VisibleEntries + 1) div 2;
    Gap := Max(Theme.StatDetail.TableColumnGap, MaxTextSize * 2);
    ThemeText.W := Trunc((FullWidth * RightBound - Gap) / 2);
    if (VisibleEntries >= Theme.StatDetail.TwoColumnMinEntries) and
       (SingleLayout.TextSize < MaxTextSize * 0.9) and (ThemeText.W > 0) then
    begin
      ListLayout := CalculateTextListLayout(TopY, BottomY,
          TrialRows + Theme.StatDetail.PaddingRows,
          Theme.StatDetail.MinTextSize, MaxTextSize,
          FontSizePerRowPitch(TrialRows, Theme.StatDetail.MinEntries,
          Theme.StatDetail.MaxEntries, Theme.StatDetail.FontSizeRelaxed,
          Theme.StatDetail.FontSizeDense, Theme.StatDetail.FontSizeCurve),
          Theme.StatDetail.LineHeight);
      while ListLayout.TextSize >= SingleLayout.TextSize * 1.1 do
      begin
        RequiredWidth := 0;
        for Column := 0 to ColumnCount - 1 do
          RequiredWidth := RequiredWidth + Table.Column[Column].GapBefore +
              Max(Table.Column[Column].Width,
              ValueColumnWidth(Definitions[Column].Header, Definitions[Column].Value));
        if RequiredWidth <= 1 then
        begin
          RowsPerColumn := TrialRows;
          ColumnOffset := ThemeText.W + Gap;
          RightBound := 1;
          Break;
        end;
        ListLayout.TextSize := ListLayout.TextSize * 0.95;
      end;
    end;
    if ColumnOffset = 0 then
    begin
      ThemeText.W := Trunc(FullWidth);
      ListLayout := SingleLayout;
    end;
    ColumnCompactFactor := EnsureRange(ListLayout.TextSize / MaxTextSize, 0.0, 1.0);
    SetLength(Specs, ColumnCount);
    for Column := 0 to ColumnCount - 1 do
    begin
      Specs[Column].Width := Table.Column[Column].Width;
      if ColumnOffset > 0 then
        Specs[Column].Width := Max(Specs[Column].Width,
            ValueColumnWidth(Definitions[Column].Header, Definitions[Column].Value))
      else if Table.Column[Column].AutoWidth then
        Specs[Column].Width := ValueColumnWidth(Definitions[Column].Header,
            Definitions[Column].Value);
      Specs[Column].GapBefore := Table.Column[Column].GapBefore;
      Specs[Column].Align := Table.Column[Column].Align;
      Specs[Column].Flexible := Table.Column[Column].Flexible;
      Specs[Column].CompactGap := Table.Column[Column].CompactGap;
    end;
    CalculateListColumns(Specs, ThemeText.X, ThemeText.W, RightBound,
        ColumnCompactFactor, Theme.StatDetail.MinColumnGap, ListColumns);
    for Column := 0 to ColumnCount - 1 do
    begin
      TextListValue[Column] := Definitions[Column].Value;
      SetColumn(Column, ListColumns[Column], Definitions[Column].Header);
    end;
  end;

begin
  RowsPerColumn := EntriesPerPage;
  ColumnOffset := 0;
  ThemeText := Theme.StatDetail.TextList[0];
  ListX := Theme.StatDetail.ListX;
  ListY := Theme.StatDetail.ListY;
  ListW := Theme.StatDetail.ListW;
  ListBottomY := Theme.StatDetail.ListBottomY;
  if (ListW <= 0) then
    ListW := ThemeText.W;
  if (ListBottomY <= ListY) then
  begin
    ListY := ThemeText.Y;
    ListBottomY := ListY + Theme.StatDetail.FallbackRowPitch *
        (EntriesPerPage + Theme.StatDetail.PaddingRows - 1);
  end;

  LayoutRows := Max(Theme.StatDetail.MinEntries, VisibleEntries) + Theme.StatDetail.PaddingRows;
  ThemeText.X := ListX;
  ThemeText.W := ListW;
  TopY := ListY;
  BottomY := ListBottomY;
  HeaderY := Theme.StatDetail.ListHeaderY;

  MaxTextSize := Max(Theme.StatDetail.MinTextSize, ThemeText.Size);
  ListLayout := CalculateTextListLayout(TopY, BottomY, LayoutRows,
      Theme.StatDetail.MinTextSize, MaxTextSize,
      FontSizePerRowPitch(EntriesPerPage, Theme.StatDetail.MinEntries,
      Theme.StatDetail.MaxEntries, Theme.StatDetail.FontSizeRelaxed,
      Theme.StatDetail.FontSizeDense, Theme.StatDetail.FontSizeCurve),
      Theme.StatDetail.LineHeight);
  HeaderSize := Theme.StatDetail.TextHeader.Size;
  ListLayout.RowPitch := Min(ListLayout.RowPitch, ListLayout.TextSize / 0.78 + 2);
  ColumnCompactFactor := EnsureRange(ListLayout.TextSize / MaxTextSize,
      0.0, 1.0);

  for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
  begin
    TextListValue[Column] := scvNone;
    Text[TextHeader[Column]].Text := '';
    Text[TextHeader[Column]].Visible := false;
    Text[TextHeaderRight[Column]].Visible := false;
  end;

  for Row := 0 to High(TextList) do
  begin
    for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
    begin
      Text[TextList[Row, Column]].Y := TopY +
          (Row + Theme.StatDetail.FirstContentRow) * ListLayout.RowPitch;
      Text[TextList[Row, Column]].H := 0;
      Text[TextList[Row, Column]].Size := ListLayout.TextSize;
      Text[TextList[Row, Column]].Visible := false;
    end;
  end;

  case Typ of
    stBestScores:
      SetColumns(Theme.StatDetail.BestScoresTable, BEST_SCORE_COLUMNS);
    stBestSingers:
      SetColumns(Theme.StatDetail.BestSingersTable, BEST_SINGER_COLUMNS);
    stMostSungSong:
      SetColumns(Theme.StatDetail.PopularTable, POPULAR_SONG_COLUMNS);
    stMostPopBand:
      SetColumns(Theme.StatDetail.PopularTable, POPULAR_BAND_COLUMNS);
  end;
  ListLayout.RowPitch := Min(ListLayout.RowPitch, ListLayout.TextSize / 0.78 + 2);
  for Row := 0 to High(TextList) do
    for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
    begin
      Text[TextList[Row, Column]].Y := TopY +
          (Row mod RowsPerColumn + Theme.StatDetail.FirstContentRow) * ListLayout.RowPitch;
      Text[TextList[Row, Column]].Size := ListLayout.TextSize;
    end;
end;

procedure TScreenStatDetail.ChangeEntriesPerPage(Delta: integer);
var
  FirstEntry: cardinal;
  NewCount: integer;
begin
  NewCount := EnsureRange(EntriesPerPage + Delta, Theme.StatDetail.MinEntries,
      Theme.StatDetail.MaxEntries);
  if (NewCount = EntriesPerPage) then
    Exit;

  FirstEntry := Page * EntriesPerPage;
  EntriesPerPage := NewCount;
  Ini.StatDetailCount := EntriesPerPage;
  Ini.SaveStatDetailCount;

  RecalculatePages;
  SetPage(FirstEntry div EntriesPerPage);
end;

procedure TScreenStatDetail.ToggleMinMedianFilter;
var
  FirstEntry: cardinal;
  NewPage: cardinal;
begin
  if (Typ <> stBestSingers) then
    Exit;

  FirstEntry := Page * EntriesPerPage;
  MinMedianFilter := not MinMedianFilter;
  TotEntrys := DataBase.GetTotalEntrys(Typ, ActiveFilters, StatSinceDate);
  RecalculatePages;
  UpdateMinMedianHint;

  NewPage := FirstEntry div EntriesPerPage;
  if (NewPage >= TotPages) then
    NewPage := TotPages - 1;
  SetPage(NewPage);
end;

procedure TScreenStatDetail.SetPage(NewPage: cardinal);
var
  StatList: TList;
  I: integer;
  Column: integer;
  PerPage: integer;
  VisibleEntries: integer;
  PageText: UTF8String;
begin
  if (NewPage >= TotPages) then
    NewPage := TotPages - 1;
  Page := NewPage;

  if (TotEntrys = 0) then
    PerPage := 0
  else if (Page + 1 = TotPages) and (TotEntrys mod EntriesPerPage <> 0) then
    PerPage := (TotEntrys mod EntriesPerPage)
  else
    PerPage := EntriesPerPage;

  try
    if DocumentUI <> nil then
      PageText := StringReplace(Format(Language.Translate('STAT_PAGE'), [Page + 1, TotPages, PerPage, TotEntrys]), '\n', ' ', [rfReplaceAll])
    else PageText := StringReplace(Format(Theme.StatDetail.PageStr,
        [Page + 1, TotPages, PerPage, TotEntrys]), '\n', ' ', [rfReplaceAll]);
  except
    on E: EConvertError do
    begin
      PageText := '';
      Log.LogError('Error Parsing FormatString in UScreenStatDetail: ' + E.Message);
    end;
  end;

  if DocumentUI = nil then Text[TextPage].Text := PageText;

  // fetch statistics
  StatList := Database.GetStats(Typ, EntriesPerPage, NewPage, ActiveFilters, StatSinceDate);
  if (StatList <> nil) then
    VisibleEntries := Min(StatList.Count, EntriesPerPage)
  else
    VisibleEntries := 0;

  if DocumentUI <> nil then
  begin
    try
      SetDocumentPage(StatList, VisibleEntries, PageText);
    finally
      Database.FreeStats(StatList);
    end;
    Exit;
  end;

  UpdateListLayout(StatList, VisibleEntries);

  // reset texts
  ClearRows;

  if (StatList <> nil) then
  begin
    for I := 0 to VisibleEntries - 1 do
      for Column := 0 to STAT_DETAIL_MAX_COLUMNS - 1 do
        SetRowText(I, Column, StatCellText(StatList, I, TextListValue[Column]));

  end;

  //Show correct Title
  SetTitle;

  Database.FreeStats(StatList);
end;

end.
