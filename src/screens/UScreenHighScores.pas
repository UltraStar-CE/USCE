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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenHighScores.pas $
 * $Id: UScreenHighScores.pas 2548 2010-06-18 11:00:21Z whiteshark0 $
 *}

unit UScreenHighScores;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UMenu,
  UMenuList,
  UMusic,
  USongs,
  USong,
  UThemes,
  sdl2,
  Math,
  SysUtils;

type
  THighScoreRow = record
    Entry: TScore;
    Difficulty: integer;
  end;

  TScreenHighScores = class(TMenu)
    private
      DisplayScores: array of THighScoreRow;
      TextDifficultyColumn: integer;
      EntryColumns: array[0..3] of TListColumn;
      EntryRowsPerColumn: integer;
      EntryColumnOffset, EntryColumnWidth: real;
      procedure BuildDisplayScores;
      procedure SelectDifficulty(Delta: integer);
      function ColumnForEntry(Column, Entry: integer): TListColumn;
      function TryTwoColumns(var Layout: TTextListLayout): boolean;
      procedure AddThemedFrame;
      procedure ApplyEntryStaticLayout(StaticIndex, EntryIndex: integer; const ThemeStatic: TThemeStatic);
      procedure ApplyEntryTextLayout(TextIndex, EntryIndex: integer; const ThemeText: TThemeText);
      procedure ApplyTextLayout(TextIndex: integer; const ThemeText: TThemeText);
      procedure ApplyStaticLayout(StaticIndex: integer; const ThemeStatic: TThemeStatic);
      procedure ChangeEntryCount(Delta: integer);
      function EntryY(EntryIndex: integer): integer;
      function FormatEntryCountText(const TextTemplate: UTF8String): UTF8String;
      procedure LoadCurrentSongScores;
      function ScaledSize(ThemeSize: integer): integer;
      procedure SetEntryVisible(EntryIndex: integer; Visible: boolean);
      procedure UpdateEntryLayout;
      procedure UpdateColumnLayout;
      procedure UpdateHeaderText;
      procedure ReturnFromScores;
    public
      TextTitle:            integer;
      TextWhereAmI:         integer;
      TextArtistTitle:      integer;
      TextDifficultyLabel:  integer;
      TextDifficulty:       integer;
      TextContinue:         integer;
      TextNavigate:         integer;
      VisibleDifficulty: integer;
      EntryCount: integer;
      LayoutEntryCount: integer;
      EntryRowPitch: real;
      EntryTextSize: real;

      EntryNumberStatic: array of integer;
      EntryNumberText:   array of integer;
      EntryNameText:     array of integer;
      EntryScoreText:    array of integer;
      EntryDateText:     array of integer;
      EntryDifficultyText: array of integer;

      IsFadingOut:    boolean;

      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      procedure OnShow; override;
      procedure OnWindowResized; override;
      procedure ShowScoresForDifficulty(difficulty: integer);
      function Draw: boolean; override;
  end;

const
  HighScoresHelpID = 'ID_024';

implementation

uses
  UDataBase,
  ULanguage,
  UInputSource,
  UGraphic,
  UHelp,
  ULog,
  UMain,
  URemoteBridgeIPC,
  UIni,
  UNote,
  UUnicodeUtils;

function TrackNumber(TrackMask: integer): integer;
begin
  if (TrackMask <= 0) or ((TrackMask and (TrackMask - 1)) <> 0) then
    Exit(0);

  Result := 1;
  while TrackMask > 1 do
  begin
    TrackMask := TrackMask shr 1;
    Inc(Result);
  end;
end;

procedure TScreenHighScores.AddThemedFrame;
var
  I: integer;
begin
  PrepareButtonCollections(Theme.HighScores.ButtonCollection);
  AddBackground(Theme.HighScores.Background);

  for I := 0 to High(Theme.HighScores.Statics) do
    AddStatic(Theme.HighScores.Statics[I]);
end;

procedure TScreenHighScores.ApplyEntryStaticLayout(StaticIndex, EntryIndex: integer; const ThemeStatic: TThemeStatic);
var
  EntryStatic: TThemeStatic;
  NewSize: integer;
begin
  EntryStatic := ThemeStatic;
  EntryStatic.Y := EntryY(EntryIndex) + Round(
      (ThemeStatic.Y - Theme.HighScores.RowNameText.Y) *
      EntryTextSize / Theme.HighScores.RowNameText.Size);

  NewSize := ScaledSize(ThemeStatic.H);
  if (ThemeStatic.H > 0) and (NewSize < ThemeStatic.H) then
  begin
    EntryStatic.H := NewSize;
    EntryStatic.W := Round(ThemeStatic.W * NewSize / ThemeStatic.H);
    EntryStatic.X := ThemeStatic.X + Round((ThemeStatic.W - EntryStatic.W) / 2);
  end;

  ApplyStaticLayout(StaticIndex, EntryStatic);
end;

procedure TScreenHighScores.ApplyEntryTextLayout(TextIndex, EntryIndex: integer; const ThemeText: TThemeText);
var
  EntryText: TThemeText;
begin
  EntryText := ThemeText;
  EntryText.Y := EntryY(EntryIndex) + Round(
      (ThemeText.Y - Theme.HighScores.RowNameText.Y) *
      EntryTextSize / Theme.HighScores.RowNameText.Size);
  EntryText.Size := ScaledSize(ThemeText.Size);
  ApplyTextLayout(TextIndex, EntryText);
end;

procedure TScreenHighScores.ApplyTextLayout(TextIndex: integer; const ThemeText: TThemeText);
begin
  PositionListColumnText(Text[TextIndex],
      ListColumnFromAnchor(ThemeText.X, ThemeText.W, ThemeText.Align));
  Text[TextIndex].Y := ThemeText.Y;
  Text[TextIndex].W := ThemeText.W;
  Text[TextIndex].H := ThemeText.H;
  Text[TextIndex].Size := ThemeText.Size;
end;

procedure TScreenHighScores.ApplyStaticLayout(StaticIndex: integer; const ThemeStatic: TThemeStatic);
begin
  Statics[StaticIndex].Texture.X := ThemeStatic.X;
  Statics[StaticIndex].Texture.Y := ThemeStatic.Y;
  Statics[StaticIndex].Texture.W := ThemeStatic.W;
  Statics[StaticIndex].Texture.H := ThemeStatic.H;
end;

procedure TScreenHighScores.ChangeEntryCount(Delta: integer);
var
  NewEntryCount: integer;
begin
  if EntryColumnOffset > 0 then
    Delta := Delta * 2;
  NewEntryCount := EntryCount + Delta;
  if (NewEntryCount < 5) then
    NewEntryCount := 5
  else if (NewEntryCount > Theme.HighScores.List.MaxEntries) then
    NewEntryCount := Theme.HighScores.List.MaxEntries;

  if (NewEntryCount = EntryCount) then
    Exit;

  EntryCount := NewEntryCount;
  Ini.HighScoreScreenEntries := EntryCount;
  Ini.SaveHighScoreScreenSettings;

  UpdateHeaderText;
  ShowScoresForDifficulty(VisibleDifficulty);
end;

function TScreenHighScores.EntryY(EntryIndex: integer): integer;
begin
  Result := Round(Theme.HighScores.RowNameText.Y +
      (EntryIndex mod EntryRowsPerColumn + 1) * EntryRowPitch);
end;

function TScreenHighScores.FormatEntryCountText(const TextTemplate: UTF8String): UTF8String;
begin
  try
    Result := Format(TextTemplate, [EntryCount]);
  except
    Result := TextTemplate;
  end;
end;

procedure TScreenHighScores.BuildDisplayScores;
var
  Level, I, J, Count: integer;
  Row: THighScoreRow;
begin
  SetLength(DisplayScores, 0);
  if CurrentSong = nil then Exit;
  for Level := 0 to 2 do
    if (VisibleDifficulty = 3) or (VisibleDifficulty = Level) then
      for I := 0 to High(CurrentSong.Score[Level]) do
      begin
        Count := Length(DisplayScores);
        SetLength(DisplayScores, Count + 1);
        DisplayScores[Count].Entry := CurrentSong.Score[Level, I];
        DisplayScores[Count].Difficulty := Level;
      end;
  // Scores stay unmodified. Equal totals retain their source-list order.
  for I := 1 to High(DisplayScores) do
  begin
    Row := DisplayScores[I];
    J := I - 1;
    while J >= 0 do
    begin
      if DisplayScores[J].Entry.Score >= Row.Entry.Score then Break;
      DisplayScores[J + 1] := DisplayScores[J];
      Dec(J);
    end;
    DisplayScores[J + 1] := Row;
  end;
end;

procedure TScreenHighScores.SelectDifficulty(Delta: integer);
var
  AllDifficulties: boolean;
begin
  VisibleDifficulty := (VisibleDifficulty + Delta + 4) mod 4;
  AllDifficulties := VisibleDifficulty = 3;
  if Ini.HighScoreScreenAllDifficulties <> AllDifficulties then
  begin
    Ini.HighScoreScreenAllDifficulties := AllDifficulties;
    Ini.SaveHighScoreScreenSettings;
  end;
  ShowScoresForDifficulty(VisibleDifficulty);
end;

procedure TScreenHighScores.LoadCurrentSongScores;
var
  I: integer;
  Report: string;
begin
  try
    DataBase.ReadScore(CurrentSong, Theme.HighScores.List.MaxEntries);
  except
    on E : Exception do
    begin
      Report := 'Reading songscore failed in highscore screen. Faulty database file?' + LineEnding +
      'Stacktrace:' + LineEnding;
      if E <> nil then
      begin
        Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
        'Message: ' + E.Message + LineEnding;
      end;
      Report := Report + BackTraceStrFunc(ExceptAddr);
      for I := 0 to ExceptFrameCount - 1 do
      begin
        Report := Report + LineEnding + BackTraceStrFunc(ExceptFrames[I]);
      end;
      Log.LogWarn(Report, 'UScreenHighScores.LoadCurrentSongScores');
    end;
  end;
end;

function TScreenHighScores.ScaledSize(ThemeSize: integer): integer;
begin
  Result := Round(ThemeSize * Min(1.0,
      EntryTextSize / Theme.HighScores.RowNameText.Size));
end;

procedure TScreenHighScores.SetEntryVisible(EntryIndex: integer; Visible: boolean);
begin
  Statics[EntryNumberStatic[EntryIndex]].Visible := Visible;
  Text[EntryNumberText[EntryIndex]].Visible := Visible;
  Text[EntryNameText[EntryIndex]].Visible := Visible;
  Text[EntryScoreText[EntryIndex]].Visible := Visible;
  Text[EntryDateText[EntryIndex]].Visible := Visible;
  Text[EntryDifficultyText[EntryIndex]].Visible := Visible and (VisibleDifficulty = 3);
end;

function TScreenHighScores.ColumnForEntry(Column, Entry: integer): TListColumn;
begin
  Result := EntryColumns[Column];
  if Entry >= EntryRowsPerColumn then
    Result.Left := Result.Left + EntryColumnOffset;
end;

function TScreenHighScores.TryTwoColumns(var Layout: TTextListLayout): boolean;
var
  Trial: TTextListLayout;
  I, HalfRows: integer;
  FullWidth, Width, FontSize, MinimumSize, ScoreWidth, DateWidth, NameWidth, RankWidth: real;
begin
  Result := false;
  if VisibleDifficulty = 3 then Exit; // four columns need the full table width
  if (LayoutEntryCount < Theme.HighScores.List.TwoColumnMinEntries) or
     (CurrentSong = nil) or (Theme.HighScores.RowNameText.Align <> 0) or
     (Theme.HighScores.RowScoreText.Align <> 2) or (Theme.HighScores.RowDateText.Align <> 2) then Exit;
  FullWidth := Theme.HighScores.RowDateText.X - Theme.HighScores.RowNumberStatic.X;
  Width := (FullWidth - Theme.HighScores.List.ColumnGap) / 2;
  if Width <= 0 then Exit;
  HalfRows := (LayoutEntryCount + 1) div 2;
  Trial := CalculateTextListLayout(Theme.HighScores.RowNameText.Y,
      Theme.HighScores.List.BottomY, HalfRows + 2, Theme.HighScores.List.MinTextSize,
      Theme.HighScores.RowNameText.Size,
      FontSizePerRowPitch(HalfRows, 5, Theme.HighScores.List.MaxEntries, 0.78, 1.10, 2.0), 0.85);
  MinimumSize := Theme.HighScores.List.MinTextSize;
  FontSize := Trial.TextSize;
  while FontSize >= MinimumSize do
  begin
    ScoreWidth := 0; DateWidth := 0; NameWidth := 0;
    for I := 0 to Min(LayoutEntryCount, Length(DisplayScores)) - 1 do
    begin
      ScoreWidth := Max(ScoreWidth, MeasureTextMaxLineWidth(
          IntToStr(DisplayScores[I].Entry.Score),
          Theme.HighScores.RowScoreText.Font, Theme.HighScores.RowScoreText.Style, FontSize));
      DateWidth := Max(DateWidth, MeasureTextMaxLineWidth(DisplayScores[I].Entry.Date,
          Theme.HighScores.RowDateText.Font, Theme.HighScores.RowDateText.Style, FontSize));
      NameWidth := Max(NameWidth, MeasureTextMaxLineWidth(DisplayScores[I].Entry.Name,
          Theme.HighScores.RowNameText.Font, Theme.HighScores.RowNameText.Style, FontSize));
    end;
    RankWidth := (Theme.HighScores.RowNameText.X - Theme.HighScores.RowNumberStatic.X) *
        FontSize / Theme.HighScores.RowNameText.Size;
    if RankWidth + ScoreWidth + DateWidth + Max(80, Min(NameWidth, 120)) + 36 <= Width then
    begin
      EntryRowsPerColumn := HalfRows;
      EntryColumnWidth := Width;
      EntryColumnOffset := Width + Theme.HighScores.List.ColumnGap;
      Layout := Trial;
      Layout.TextSize := FontSize;
      Result := true;
      Exit;
    end;
    FontSize := FontSize * 0.95;
  end;
end;

procedure TScreenHighScores.UpdateEntryLayout;
var
  I: integer;
  LayoutIndex: integer;
  LayoutRows: integer;
  Layout: TTextListLayout;
begin
  EntryRowsPerColumn := Max(1, LayoutEntryCount);
  EntryColumnOffset := 0;
  EntryColumnWidth := 0;
  LayoutRows := LayoutEntryCount + 2;
  Layout := CalculateTextListLayout(Theme.HighScores.RowNameText.Y,
      Theme.HighScores.List.BottomY, LayoutRows,
      Theme.HighScores.List.MinTextSize, Theme.HighScores.RowNameText.Size,
      FontSizePerRowPitch(LayoutEntryCount, 5, Theme.HighScores.List.MaxEntries, 0.78, 1.10, 2.0), 0.85);
  TryTwoColumns(Layout);
  Layout.RowPitch := Min(Layout.RowPitch, Layout.TextSize / 0.78 + 2);
  EntryTextSize := Layout.TextSize;
  EntryRowPitch := Layout.RowPitch;

  for I := 0 to High(EntryNumberStatic) do
  begin
    if (I < LayoutEntryCount) then
      LayoutIndex := I
    else
      LayoutIndex := LayoutEntryCount - 1;

    ApplyEntryStaticLayout(EntryNumberStatic[I], LayoutIndex, Theme.HighScores.RowNumberStatic);

    ApplyEntryTextLayout(EntryNumberText[I], LayoutIndex,
      Theme.HighScores.RowNumberText);
    ApplyEntryTextLayout(EntryNameText[I], LayoutIndex,
      Theme.HighScores.RowNameText);
    ApplyEntryTextLayout(EntryScoreText[I], LayoutIndex,
      Theme.HighScores.RowScoreText);
    ApplyEntryTextLayout(EntryDateText[I], LayoutIndex,
      Theme.HighScores.RowDateText);
    ApplyEntryTextLayout(EntryDifficultyText[I], LayoutIndex,
      Theme.HighScores.RowDifficultyText);
    if EntryColumnOffset > 0 then
    begin
      Statics[EntryNumberStatic[I]].Texture.X := Theme.HighScores.RowNumberStatic.X;
      if I >= EntryRowsPerColumn then
        Statics[EntryNumberStatic[I]].Texture.X := Statics[EntryNumberStatic[I]].Texture.X + EntryColumnOffset;
      Text[EntryNumberText[I]].X := Statics[EntryNumberStatic[I]].Texture.X +
          Statics[EntryNumberStatic[I]].Texture.W / 2;
    end;
  end;
end;

procedure TScreenHighScores.UpdateColumnLayout;
var
  Specs: array of TListColumnSpec;
  Columns: array[0..3] of TListColumn;
  I, Pass, RowCount, ScoreColumn: integer;
  Left, Width, Gap, ScoreDateGap, ScoreWidth, DateWidth, DifficultyWidth, FixedWidth, Scale: real;
begin
  EntryColumns[0] := ListColumnFromAnchor(Theme.HighScores.RowNameText.X,
      Theme.HighScores.RowNameText.W, Theme.HighScores.RowNameText.Align);
  EntryColumns[1] := ListColumnFromAnchor(Theme.HighScores.RowScoreText.X,
      Theme.HighScores.RowScoreText.W, Theme.HighScores.RowScoreText.Align);
  EntryColumns[2] := ListColumnFromAnchor(Theme.HighScores.RowDateText.X,
      Theme.HighScores.RowDateText.W, Theme.HighScores.RowDateText.Align);

  // Keep custom theme anchors; infer widths only for the standard column order.
  if (VisibleDifficulty <> 3) and
     ((EntryColumns[0].Align <> 0) or (EntryColumns[1].Align <> 2) or
      (EntryColumns[2].Align <> 2)) then
    Exit;
  Left := Theme.HighScores.RowNameText.X;
  Width := Theme.HighScores.RowDateText.X - Left;
  if VisibleDifficulty = 3 then
  begin
    Left := Min(EntryColumns[0].Left, Min(EntryColumns[1].Left, EntryColumns[2].Left));
    Width := Max(EntryColumns[0].Left + EntryColumns[0].Width,
        Max(EntryColumns[1].Left + EntryColumns[1].Width,
            EntryColumns[2].Left + EntryColumns[2].Width)) - Left;
  end;
  if EntryColumnOffset > 0 then
  begin
    Left := Theme.HighScores.RowNumberStatic.X +
        (Theme.HighScores.RowNameText.X - Theme.HighScores.RowNumberStatic.X) *
        EntryTextSize / Theme.HighScores.RowNameText.Size;
    Width := EntryColumnWidth - (Left - Theme.HighScores.RowNumberStatic.X);
  end;
  Gap := 12 * Min(1.0, EntryTextSize / Theme.HighScores.RowNameText.Size);
  if (Width <= 0) or ((VisibleDifficulty <> 3) and
     ((Theme.HighScores.RowScoreText.X <= Left) or
      (Theme.HighScores.RowDateText.X <= Theme.HighScores.RowScoreText.X + Gap))) then
    Exit;

  ScoreDateGap := 48;
  if EntryColumnOffset > 0 then ScoreDateGap := 12;
  RowCount := Min(EntryCount, Length(DisplayScores));
  // Reserve measured score and date widths, leaving at least a quarter for names.
  // On narrow layouts reduce the numeric font sizes together instead of truncating.
  for Pass := 0 to 10 do
  begin
    ScoreWidth := 2;
    DateWidth := 2;
    DifficultyWidth := 0;
    if VisibleDifficulty = 3 then
      DifficultyWidth := 2 + MeasureTextMaxLineWidth(Text[TextDifficultyColumn].Text,
          Text[EntryDifficultyText[0]].Font, Text[EntryDifficultyText[0]].Style,
          Text[EntryDifficultyText[0]].Size);
    for I := 0 to RowCount - 1 do
    begin
      ScoreWidth := Max(ScoreWidth, 2 + MeasureTextMaxLineWidth(
          IntToStr(DisplayScores[I].Entry.Score),
          Text[EntryScoreText[I]].Font, Text[EntryScoreText[I]].Style,
          Text[EntryScoreText[I]].Size));
      DateWidth := Max(DateWidth, 2 + MeasureTextMaxLineWidth(
          DisplayScores[I].Entry.Date,
          Text[EntryDateText[I]].Font, Text[EntryDateText[I]].Style,
          Text[EntryDateText[I]].Size));
      if VisibleDifficulty = 3 then
        DifficultyWidth := Max(DifficultyWidth, 2 + MeasureTextMaxLineWidth(
            IDifficultyTranslated[DisplayScores[I].Difficulty],
            Text[EntryDifficultyText[I]].Font, Text[EntryDifficultyText[I]].Style,
            Text[EntryDifficultyText[I]].Size));
    end;
    FixedWidth := ScoreWidth + DateWidth;
    if VisibleDifficulty = 3 then FixedWidth := FixedWidth + DifficultyWidth + Gap;
    if (FixedWidth <= Width * 0.75 - Gap - ScoreDateGap) or (Pass = 10) then
      Break;
    Scale := Max(0.1, (Width * 0.75 - Gap - ScoreDateGap - 4) / FixedWidth);
    for I := 0 to High(EntryScoreText) do
    begin
      Text[EntryScoreText[I]].Size := Text[EntryScoreText[I]].Size * Scale;
      Text[EntryDateText[I]].Size := Text[EntryDateText[I]].Size * Scale;
      if VisibleDifficulty = 3 then
        Text[EntryDifficultyText[I]].Size := Text[EntryDifficultyText[I]].Size * Scale;
    end;
  end;

  SetLength(Specs, 3 + Ord(VisibleDifficulty = 3));
  Specs[0].Flexible := true;
  ScoreColumn := 1;
  if VisibleDifficulty = 3 then
  begin
    Specs[1].GapBefore := Gap / Width;
    Specs[1].Width := DifficultyWidth / Width;
    ScoreColumn := 2;
  end;
  Specs[ScoreColumn].GapBefore := Gap / Width;
  Specs[ScoreColumn].Width := ScoreWidth / Width;
  Specs[ScoreColumn].Align := 2;
  Specs[ScoreColumn + 1].GapBefore := ScoreDateGap / Width;
  Specs[ScoreColumn + 1].Width := DateWidth / Width;
  Specs[ScoreColumn + 1].Align := 2;
  CalculateListColumns(Specs, Left, Width, 1.0, 1.0, 1.0, Columns);
  EntryColumns[0] := Columns[0];
  EntryColumns[1] := Columns[ScoreColumn];
  EntryColumns[2] := Columns[ScoreColumn + 1];
  if VisibleDifficulty = 3 then EntryColumns[3] := Columns[1];
  if Theme.HighScores.RowNameText.W > 0 then
    EntryColumns[0].Width := Min(Theme.HighScores.RowNameText.W, EntryColumns[0].Width);
  for I := 0 to High(EntryNameText) do
  begin
    PositionListColumnText(Text[EntryNameText[I]], ColumnForEntry(0, I));
    PositionListColumnText(Text[EntryScoreText[I]], ColumnForEntry(1, I));
    PositionListColumnText(Text[EntryDateText[I]], ColumnForEntry(2, I));
    Text[EntryNameText[I]].W := EntryColumns[0].Width;
    Text[EntryScoreText[I]].W := EntryColumns[1].Width;
    Text[EntryDateText[I]].W := EntryColumns[2].Width;
    if VisibleDifficulty = 3 then
    begin
      PositionListColumnText(Text[EntryDifficultyText[I]], ColumnForEntry(3, I));
      Text[EntryDifficultyText[I]].W := EntryColumns[3].Width;
    end;
  end;
  if VisibleDifficulty = 3 then
  begin
    PositionListColumnText(Text[TextDifficultyColumn], EntryColumns[3]);
    Text[TextDifficultyColumn].W := EntryColumns[3].Width;
    Text[TextDifficultyColumn].Y := Text[EntryDifficultyText[0]].Y - EntryRowPitch;
    Text[TextDifficultyColumn].Size := Text[EntryDifficultyText[0]].Size;
  end;
end;

procedure TScreenHighScores.UpdateHeaderText;
begin
  Text[TextTitle].Text := FormatEntryCountText(Theme.HighScores.TextTitle.Text);
  Text[TextWhereAmI].Text := FormatEntryCountText(Theme.HighScores.TextWhereAmI.Text);
end;

procedure TScreenHighScores.ReturnFromScores;
begin
  if (ScreenSong.Mode in [smPartyClassic, smPartyFree]) and ScreenSing.LocalHighscoresAllowed then
    FadeTo(@ScreenPartyScore)
  else
  begin
    ScreenSong.PreservePreviewForReturn;
    FadeTo(@ScreenSong);
  end;
end;

function TScreenHighScores.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
begin
  if ScreenContinuousPlayback.HandlePlaybackKey(PressedKey, PressedDown, Repeated) then Exit(true);
  Result := true;
  if PressedDown then
  begin
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
      SDLK_BACKSPACE,
      SDLK_RETURN:
        begin
          if (not IsFadingOut) then
          begin
            ReturnFromScores;
            IsFadingOut := true;
          end;
        end;
      SDLK_TAB: InteractTab;
      SDLK_F1:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_RIGHT:
        begin
          SelectDifficulty(1);
        end;
      SDLK_LEFT:
        begin
          SelectDifficulty(-1);
        end;
      SDLK_UP:
        begin
          ChangeEntryCount(-1);
        end;
      SDLK_DOWN:
        begin
          ChangeEntryCount(1);
        end;
    end;
  end;
end;

function TScreenHighScores.ParseMouse(MouseButton: integer;
                                      BtnDown: boolean;
                                      X, Y: integer): boolean;
begin
  Result := true;
  if (MouseButton = SDL_BUTTON_LEFT) and BtnDown then
    //left-click anywhere sends return
    ParseInput(SDLK_RETURN, 0, true);
end;

constructor TScreenHighScores.Create;
var
  I: integer;
  ThemeText: TThemeText;
begin
  inherited Create;
  EntryCount := EnsureRange(Ini.HighScoreScreenEntries, 5, Theme.HighScores.List.MaxEntries);
  LayoutEntryCount := 5;
  SetLength(EntryNumberStatic, Theme.HighScores.List.MaxEntries);
  SetLength(EntryNumberText, Theme.HighScores.List.MaxEntries);
  SetLength(EntryNameText, Theme.HighScores.List.MaxEntries);
  SetLength(EntryScoreText, Theme.HighScores.List.MaxEntries);
  SetLength(EntryDateText, Theme.HighScores.List.MaxEntries);
  SetLength(EntryDifficultyText, Theme.HighScores.List.MaxEntries);

  AddThemedFrame;

  TextTitle := AddText(Theme.HighScores.TextTitle);
  TextWhereAmI := AddText(Theme.HighScores.TextWhereAmI);
  TextArtistTitle := AddText(Theme.HighScores.TextArtistTitle);
  TextDifficultyLabel := AddText(Theme.HighScores.TextDifficultyLabel);
  TextDifficulty := AddText(Theme.HighScores.TextDifficulty);
  TextContinue := AddText(Theme.HighScores.TextContinue);
  TextNavigate := AddText(Theme.HighScores.TextNavigate);

  for I := 0 to Theme.HighScores.List.MaxEntries - 1 do
  begin
    EntryNumberStatic[I] := AddStatic(Theme.HighScores.RowNumberStatic);

    ThemeText := Theme.HighScores.RowNumberText;
    ThemeText.Text := IntToStr(I + 1);
    EntryNumberText[I] := AddText(ThemeText);

    EntryNameText[I] := AddText(Theme.HighScores.RowNameText);
    EntryScoreText[I] := AddText(Theme.HighScores.RowScoreText);
    EntryDateText[I] := AddText(Theme.HighScores.RowDateText);
    EntryDifficultyText[I] := AddText(Theme.HighScores.RowDifficultyText);
    Text[EntryDifficultyText[I]].Visible := false;
  end;

  TextDifficultyColumn := AddText(Theme.HighScores.RowDifficultyText);
  Text[TextDifficultyColumn].Visible := false;
  UpdateEntryLayout;
  UpdateHeaderText;
end;

procedure TScreenHighScores.OnWindowResized;
begin
  inherited;
  if CurrentSong <> nil then ShowScoresForDifficulty(VisibleDifficulty);
end;

procedure TScreenHighScores.OnShow;
var PreviewEnd: real; I: integer;
begin
  inherited;
  ScreenSong.StartFinishedSong(CurrentSong, PreviewEnd);
  AudioPlayback.SetVolume(EnsureRange(Ini.PreviewVolume, 0, 100) / 100);

  if not Help.SetHelpID(HighScoresHelpID) then
    Log.LogWarn('No Entry for Help-ID ' + HighScoresHelpID, 'ScreenHighScores');

  IsFadingOut := false;
  VisibleDifficulty := EnsureRange(Ini.Difficulty, 0, 2);
  // Sparse mic assignments leave earlier player cards unassigned. Use the
  // first singer's captured input, including when the phone has since left.
  for I := 0 to Min(PlayersPlay, Length(Player)) - 1 do
    if Player[I].InputSource <> Ord(pisNone) then
    begin
      VisibleDifficulty := EnsureRange(Player[I].Level, 0, 2);
      Break;
    end;
  if ScreenSong.Mode in [smPartyClassic, smPartyFree] then VisibleDifficulty := EnsureRange(Ini.Difficulty, 0, 2);

  UpdateEntryLayout;
  UpdateHeaderText;
  LoadCurrentSongScores;

  Text[TextArtistTitle].Text := CurrentSong.Artist + ' - ' + CurrentSong.Title;

  if Ini.HighScoreScreenAllDifficulties then VisibleDifficulty := 3;
  if (VisibleDifficulty < 3) and
     (Length(CurrentSong.Score[VisibleDifficulty]) = 0) then
    VisibleDifficulty := 3;
  BuildDisplayScores;

  // An explicitly timed continuous-mode screen also stays visible when this
  // difficulty has no saved scores yet.
  if (Length(DisplayScores) = 0) and
     not ScreenContinuousPlayback.Session.Active then
  begin
    // Redirecting from OnShow replaces the pending screen before OnHide runs.
    Background.OnFinish;
    ReturnFromScores;
  end;

  ShowScoresForDifficulty(VisibleDifficulty);
end;

procedure TScreenHighScores.ShowScoresForDifficulty(difficulty: integer);
var
  I:    integer;
  Track: integer;
  Name: UTF8String;
  EntriesJson: string;
begin
  VisibleDifficulty := EnsureRange(difficulty, 0, 3);
  BuildDisplayScores;
  Text[TextDifficultyColumn].Visible := VisibleDifficulty = 3;
  LayoutEntryCount := EnsureRange(Length(DisplayScores), 5, EntryCount);
  UpdateEntryLayout;
  UpdateColumnLayout;

  for I := 0 to High(EntryNumberStatic) do
  begin
    if (I < EntryCount) and (I < Length(DisplayScores)) then
    begin
      SetEntryVisible(I, true);
      Name := DisplayScores[I].Entry.Name;
      Track := TrackNumber(DisplayScores[I].Entry.TrackMask);
      if CurrentSong.IsDuet and (Track > 0) then
        Name := Name + ' (P' + IntToStr(Track) + ')';
      SetListCellText(Text[EntryNameText[I]], ColumnForEntry(0, I), Name);
      SetListCellText(Text[EntryScoreText[I]], ColumnForEntry(1, I),
          IntToStr(DisplayScores[I].Entry.Score));
      SetListCellText(Text[EntryDateText[I]], ColumnForEntry(2, I), DisplayScores[I].Entry.Date);
      if VisibleDifficulty = 3 then
        SetListCellText(Text[EntryDifficultyText[I]], ColumnForEntry(3, I),
            IDifficultyTranslated[DisplayScores[I].Difficulty]);
    end
    else
      SetEntryVisible(I, false);
  end;

  if VisibleDifficulty = 3 then
    Text[TextDifficulty].Text := Language.Translate('OPTION_VALUE_ALL')
  else
    Text[TextDifficulty].Text := IDifficultyTranslated[VisibleDifficulty];
  EntriesJson := '[';
  for I := 0 to Min(EntryCount, Length(DisplayScores)) - 1 do
  begin
    if I > 0 then EntriesJson := EntriesJson + ',';
    EntriesJson := EntriesJson + '{"name":"' +
      RemoteJsonEscape(DisplayScores[I].Entry.Name) + '","score":' +
      IntToStr(DisplayScores[I].Entry.Score) + ',"date":"' +
      RemoteJsonEscape(DisplayScores[I].Entry.Date) + '","difficulty":' +
      IntToStr(DisplayScores[I].Difficulty) + '}';
  end;
  EntriesJson := EntriesJson + ']';
  RemoteBridgeIPC.SendGameState('high_scores', 0, 0);
  RemoteBridgeIPC.SendJsonMessage('{"type":"screen.info","protocol":1,"screen":"high_scores"' +
    ',"title":"' + RemoteJsonEscape(CurrentSong.Title) + '","artist":"' +
    RemoteJsonEscape(CurrentSong.Artist) + '","difficulty":"' +
    RemoteJsonEscape(Text[TextDifficulty].Text) + '","entries":' + EntriesJson + '}');
end;

function TScreenHighScores.Draw: boolean;
begin
  ScreenSong.UpdateTransitionPreview;
  Result := inherited Draw;
  ScreenContinuousPlayback.Update;
end;

end.
