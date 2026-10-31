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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/base/USongs.pas $
 * $Id: USongs.pas 3103 2014-11-22 23:21:19Z k-m_schindler $
 *}

unit USongs;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

{$IFDEF DARWIN}
  {$IFDEF DEBUG}
    {$DEFINE USE_PSEUDO_THREAD}
  {$ENDIF}
{$ENDIF}

uses
  SysUtils,
  Classes,
  {$IFDEF MSWINDOWS}
    Windows,
  {$ELSE}
    {$IFNDEF DARWIN}
    syscall,
    {$ENDIF}
    baseunix,
    UnixType,
  {$ENDIF}
  UPlatform,
  ULog,
  UCommon,
  {$IFDEF USE_PSEUDO_THREAD}
  PseudoThread,
  {$ENDIF}
  UPath,
  UPlaylist,
  USong,
  UIni,
  UCatCovers;

type
  TSongFilter = (
    fltAll,
    fltTitle,
    fltArtist,
    fltLanguage,
    fltEdition,
    fltGenre,
    fltYear,
    fltCreator,
    fltTags,
    fltAge,
    fltFolder
  );

  TSongFilterRow = record
    Kind: TSongFilter;
    Query: UTF8String;
  end;
  TSongFilterRows = array of TSongFilterRow;
  TSongFilterMask = array of boolean;

  TScore = record
    Name:   UTF8String;
    Score:  integer;
    Length: string;
  end;

  {$IFDEF USE_PSEUDO_THREAD}
  TSongs = class(TPseudoThread)
  {$ELSE}
  TSongs = class(TThread)
  {$ENDIF}
  private
    fParseSongDirectory: boolean;
    fProcessing:         boolean;
    fDiscoveringDirectories: boolean;
    fDiscoveryDirCount:  integer;
    fDiscoveryDirsScanned: integer;
    fTotalSongsToLoad:   integer;
    fSongsLoaded:        integer;
    fReloadAfterLockdown: boolean;
    function CollectSongFiles: TPathDynArray;
    procedure int_LoadSongList;
    procedure DoDirChanged(Sender: TObject);
    procedure LoadSongFromFile(const FilePath: IPath);
    procedure UpdateDiscoveryProgress(SongsFound: integer; Force: boolean = false);
    procedure UpdateSongLoadingProgress(Force: boolean = false);
  protected
    procedure Execute; override;
  public
    SongList: TList;            // array of songs

    Selected: integer;        // selected song index
    constructor Create();
    destructor  Destroy(); override;

    procedure LoadSongList;     // load all songs
    procedure ReplayDeferredReload;
  procedure FindFilesByExtension(const Dir: IPath; const Ext: IPath; Recursive: Boolean; var Files: TPathDynArray);
    procedure Sort(Order: TSortingType);
    property  Processing: boolean read fProcessing;
  end;

  TCatSongs = class
    Song:       array of TSong; // array of categories with songs
    SongSort:   array of TSong;

    Selected:   integer; // selected song index
    Order:      integer; // order type (0=title)
    CatNumShow: integer; // Category Number being seen
    CatCount:   integer; // Number of Categorys
    LastVisChecked: integer; // The real index of the last song that had its VisibilityIndex updated
    LastVisIndex:   integer; // The VisibilityIndex of the last song that had this value updated

    procedure SortSongs();
    procedure Refresh;                                      // refreshes arrays by recreating them from Songs array
    procedure ShowCategory(Index: integer);                 // expands all songs in category
    procedure HideCategory(Index: integer);                 // hides all songs in category
    procedure ClickCategoryButton(Index: integer);          // uses ShowCategory and HideCategory when needed
    procedure ShowCategoryList;                             // Hides all Songs And Show the List of all Categorys
    procedure ResetVisibleIndexCache;
    function FindNextVisible(SearchFrom: integer): integer; // Find Next visible Song
    function FindPreviousVisible(SearchFrom: integer): integer; // Find Previous visible Song
    function VisibleSongs: integer;                         // returns number of visible songs (for tabs)
    function VisibleIndex(Index: integer): integer;         // returns visible song index (skips invisible)

    function SetFilter(FilterStr: UTF8String; Filter: TSongFilter): cardinal;
    function SetFilters(const Rows: TSongFilterRows): cardinal;
    function FilterMask(const Rows: TSongFilterRows; ExceptRow: integer): TSongFilterMask;
  end;

var
  Songs:    TSongs;    // all songs
  CatSongs: TCatSongs; // categorized songs

const
  IN_ACCESS        = $00000001; //* File was accessed */
  IN_MODIFY        = $00000002; //* File was modified */
  IN_ATTRIB        = $00000004; //* Metadata changed */
  IN_CLOSE_WRITE   = $00000008; //* Writtable file was closed */
  IN_CLOSE_NOWRITE = $00000010; //* Unwrittable file closed */
  IN_OPEN          = $00000020; //* File was opened */
  IN_MOVED_FROM    = $00000040; //* File was moved from X */
  IN_MOVED_TO      = $00000080; //* File was moved to Y */
  IN_CREATE        = $00000100; //* Subfile was created */
  IN_DELETE        = $00000200; //* Subfile was deleted */
  IN_DELETE_SELF   = $00000400; //* Self was deleted */


implementation

uses
  ULanguage, UFolderFilter, UFilterTerms,
  UAge,
  ULibraryLockdown,
  StrUtils,
  SDL2,
  UCommandLine,
  UFiles,
  UGraphic,
  UMain,
  UPathUtils,
  UNote,
  UFilesystem,
  UUnicodeUtils;

var
  LastLoadingEventPumpTicks: cardinal = 0;

procedure PumpLoadingEvents;
const
  LoadingEventPumpIntervalMs = 50;
var
  Event: TSDL_Event;
  NowTicks: cardinal;
begin
  NowTicks := SDL_GetTicks;
  if (LastLoadingEventPumpTicks <> 0) and (NowTicks - LastLoadingEventPumpTicks < LoadingEventPumpIntervalMs) then
    Exit;

  while SDL_PollEvent(@Event) <> 0 do
    ;

  LastLoadingEventPumpTicks := NowTicks;
end;

function CollectDirectories(const StartDir: IPath; Recursive: Boolean; Owner: TSongs = nil): TPathDynArray;
var
  Iter: IFileIterator;
  FileInfo: TFileInfo;
  FileName: IPath;
  SubDirs: TPathDynArray;
  SubDirCount, SubDirIdx: Integer;
begin
  SetLength(Result, 1);
  Result[0] := StartDir;
  if Assigned(Owner) then
  begin
    Inc(Owner.fDiscoveryDirCount);
    Owner.UpdateDiscoveryProgress(0);
    PumpLoadingEvents;
  end;
  if not Recursive then
    Exit;

  Iter := FileSystem.FileFind(StartDir.Append('*'), faDirectory);
  while Iter.HasNext do
  begin
    FileInfo := Iter.Next;
    FileName := FileInfo.Name;
    if ((FileInfo.Attr and faDirectory) <> 0) and
       (not FileName.Equals('.')) and
       (not FileName.Equals('..')) and
       (not FileName.Equals('')) then
    begin
      Log.LogDebug('Recursing: ' + StartDir.Append(FileName).ToWide, 'TSongs.FindFilesByExtension');
      SubDirs := CollectDirectories(StartDir.Append(FileName), true, Owner);
      SubDirCount := Length(SubDirs);
      if SubDirCount > 0 then
      begin
        SetLength(Result, Length(Result) + SubDirCount);
        for SubDirIdx := 0 to SubDirCount - 1 do
          Result[High(Result) - SubDirCount + 1 + SubDirIdx] := SubDirs[SubDirIdx];
      end;
    end;
  end;
end;

constructor TSongs.Create();
begin
  // do not start thread BEFORE initialization (suspended = true)
  inherited Create(true);
  Self.FreeOnTerminate := true;

  SongList           := TList.Create();

  // until it is fixed, simply load the song-list
  int_LoadSongList();
end;

destructor TSongs.Destroy();
begin
  FreeAndNil(SongList);

  inherited;
end;

procedure TSongs.DoDirChanged(Sender: TObject);
begin
  LoadSongList();
end;

procedure TSongs.Execute();
begin
{$IFDEF USE_PSEUDO_THREAD}
  int_LoadSongList();
{$ELSE}
  fParseSongDirectory := true;

  while not terminated do
  begin

    if fParseSongDirectory then
    begin
      Log.LogStatus('Calling int_LoadSongList', 'TSongs.Execute');
      int_LoadSongList();
    end;

    Suspend();
  end;
{$ENDIF}
end;

procedure TSongs.int_LoadSongList;
var
  I: integer;
  SongFiles: TPathDynArray;
begin
  if LibraryLockdown.Active then
  begin
    fReloadAfterLockdown := true;
    Exit;
  end;
  SetLength(SongFiles, 0);
  try
    fProcessing := true;

    Log.LogStatus('Searching For Songs', 'SongList');

    fDiscoveringDirectories := false;
    fDiscoveryDirCount := 0;
    fDiscoveryDirsScanned := 0;
    fSongsLoaded := 0;
    fTotalSongsToLoad := 0;
    if Assigned(ScreenLoading) then
    begin
      ScreenLoading.SetDiscoveryProgress(0, 0, 0);
      ScreenLoading.SetSongLoadingProgress(0, 0);
      ScreenLoading.RefreshProgress(true);
    end;

    SongFiles := CollectSongFiles;

    fTotalSongsToLoad := Length(SongFiles);
    UpdateDiscoveryProgress(fTotalSongsToLoad, true);
    UpdateSongLoadingProgress(true);

    for I := 0 to High(SongFiles) do
    begin
      LoadSongFromFile(SongFiles[I]);
      Inc(fSongsLoaded);
      UpdateSongLoadingProgress;
      PumpLoadingEvents;
    end;

    if fTotalSongsToLoad > 0 then
      UpdateSongLoadingProgress(true);

    if assigned(CatSongs) then
      CatSongs.Refresh;

    if assigned(CatCovers) then
      CatCovers.Load;

    if assigned(ScreenSong)  then
    begin
      ScreenSong.GenerateThumbnails();
      ScreenSong.OnShow; // refresh ScreenSong
    end;

  finally
    SetLength(SongFiles, 0);
    Log.LogStatus('Search Complete', 'SongList');

    fParseSongDirectory := false;
    fProcessing         := false;
  end;
end;


procedure TSongs.LoadSongList;
begin
  if LibraryLockdown.Active then
  begin
    fReloadAfterLockdown := true;
    Exit;
  end;
  fParseSongDirectory := true;
  Resume();
end;

procedure TSongs.ReplayDeferredReload;
begin
  if not fReloadAfterLockdown then
    Exit;

  fReloadAfterLockdown := false;
  LoadSongList;
end;

procedure TSongs.FindFilesByExtension(const Dir: IPath; const Ext: IPath; Recursive: Boolean; var Files: TPathDynArray);
var
  DirList: TPathDynArray;
  DirIndex: Integer;
  Iter: IFileIterator;
  FileInfo: TFileInfo;
  FileName: IPath;
  FileCount: Integer;
begin
  if Recursive then
    DirList := CollectDirectories(Dir, true, Self)
  else
  begin
    SetLength(DirList, 1);
    DirList[0] := Dir;
  end;

  FileCount := 0;
  SetLength(Files, 128);
  for DirIndex := 0 to High(DirList) do
  begin
    Iter := FileSystem.FileFind(DirList[DirIndex].Append('*.txt'), 0);
    while Iter.HasNext do
    begin
      FileInfo := Iter.Next;
      FileName := FileInfo.Name;
      if ((FileInfo.Attr and faDirectory) = 0) and Ext.Equals(FileName.GetExtension(), true) then
      begin
        Log.LogDebug('Found file ' + DirList[DirIndex].Append(FileName).ToWide, 'TSongs.FindFilesByExtension');
        if (Length(Files) <= FileCount) then
        begin
          SetLength(Files, Length(Files)*2);
        end;
        Files[FileCount] := DirList[DirIndex].Append(FileName);
        FileCount := FileCount + 1;
        PumpLoadingEvents;
      end;
    end;
  end;
  SetLength(Files, FileCount);
end;

function TSongs.CollectSongFiles: TPathDynArray;
var
  DirIndex, FileIndex, AppendIndex, AdditionalCount, ScanIndex: integer;
  DirList: TPathDynArray;
  AllDirs: TPathDynArray;
  DirFiles: TPathDynArray;
  Extension: IPath;
  DirPath: IPath;
begin
  SetLength(Result, 0);
  SetLength(AllDirs, 0);

  // -song: load only the given file instead of scanning the song folders
  if Params.Song.IsSet then
  begin
    SetLength(Result, 1);
    Result[0] := Params.Song;
    Exit;
  end;

  if SongPaths = nil then
    Exit;

  Extension := Path('.txt');
  fDiscoveringDirectories := true;
  UpdateDiscoveryProgress(0, true);

  for DirIndex := 0 to SongPaths.Count - 1 do
  begin
    DirPath := SongPaths[DirIndex] as IPath;
    Log.LogDebug('Searching directory ' + DirPath.ToWide + ' for txt files', 'TSongs.CollectSongFiles');
    DirList := CollectDirectories(DirPath, true, Self);
    AdditionalCount := Length(DirList);
    if AdditionalCount > 0 then
    begin
      AppendIndex := Length(AllDirs);
      SetLength(AllDirs, AppendIndex + AdditionalCount);
      for FileIndex := 0 to AdditionalCount - 1 do
        AllDirs[AppendIndex + FileIndex] := DirList[FileIndex];
    end;
  end;

  fDiscoveringDirectories := false;
  fDiscoveryDirCount := Length(AllDirs);
  fDiscoveryDirsScanned := 0;
  UpdateDiscoveryProgress(0, true);

  for ScanIndex := 0 to High(AllDirs) do
  begin
    SetLength(DirFiles, 0);
    FindFilesByExtension(AllDirs[ScanIndex], Extension, false, DirFiles);
    AdditionalCount := Length(DirFiles);
    if AdditionalCount > 0 then
    begin
      AppendIndex := Length(Result);
      SetLength(Result, AppendIndex + AdditionalCount);
      for FileIndex := 0 to AdditionalCount - 1 do
        Result[AppendIndex + FileIndex] := DirFiles[FileIndex];
    end;

    Inc(fDiscoveryDirsScanned);
    UpdateDiscoveryProgress(Length(Result));
    PumpLoadingEvents;
    SetLength(DirFiles, 0);
  end;
end;

procedure TSongs.LoadSongFromFile(const FilePath: IPath);
var
  Song: TSong;
begin
  Song := TSong.Create(FilePath);

  if Song.Analyse(false, false, false, 0, Params.CheckSongs) then
    SongList.Add(Song)
  else
  begin
    Log.LogError('AnalyseFile failed for "' + FilePath.ToNative + '".');
    FreeAndNil(Song);
  end;
end;

procedure TSongs.UpdateDiscoveryProgress(SongsFound: integer; Force: boolean = false);
var
  Percent: integer;
  FilesNeeded: integer;
begin
  if not Assigned(ScreenLoading) then
    Exit;

  if fDiscoveringDirectories then
  begin
    FilesNeeded := 0;
    Percent := 0;
    while (Percent < 99) and (fDiscoveryDirCount >= FilesNeeded + 5 * (Percent + 1)) do
    begin
      Inc(Percent);
      Inc(FilesNeeded, 5 * Percent);
    end;
    ScreenLoading.SetDiscoveryProgress(Percent, 200, SongsFound);
  end
  else if fDiscoveryDirCount > 0 then
    ScreenLoading.SetDiscoveryProgress(fDiscoveryDirCount + fDiscoveryDirsScanned, fDiscoveryDirCount * 2, SongsFound)
  else
    ScreenLoading.SetDiscoveryProgress(0, 100, SongsFound);

  if Force then
    ScreenLoading.RefreshProgress(true);
end;

procedure TSongs.UpdateSongLoadingProgress(Force: boolean = false);
begin
  if not Assigned(ScreenLoading) then
    Exit;

  ScreenLoading.SetSongLoadingProgress(fSongsLoaded, fTotalSongsToLoad);
  if Force then
    ScreenLoading.RefreshProgress(true);
end;

(*
 * Comparison functions for sorting
 *)

function CompareByEdition(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Edition, TSong(Song2).Edition);
end;

function CompareByGenre(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Genre, TSong(Song2).Genre);
end;

function CompareByTitle(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Title, TSong(Song2).Title);
end;

function CompareByArtist(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Artist, TSong(Song2).Artist);
end;

function CompareByFolder(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Folder, TSong(Song2).Folder);
end;

function CompareByLanguage(Song1, Song2: Pointer): integer;
begin
  Result := UTF8CompareText(TSong(Song1).Language, TSong(Song2).Language);
end;

function CompareByYear(Song1, Song2: Pointer): integer;
begin
  if (TSong(Song1).Year > TSong(Song2).Year) then
    Result := 1
  else
    Result := 0;
end;

function CompareByYearReversed(Song1, Song2: Pointer): integer;
begin
  if (TSong(Song1).Year < TSong(Song2).Year) then
    Result := 1
  else
    Result := 0;
end;

procedure TSongs.Sort(Order: TSortingType);
var
  CompareFunc: TListSortCompare;
begin
  // FIXME: what is the difference between artist and artist2, etc.?
  case Order of
    sEdition: // by edition
      CompareFunc := CompareByEdition;
    sGenre: // by genre
      CompareFunc := CompareByGenre;
    sTitle: // by title
      CompareFunc := CompareByTitle;
    sArtist: // by artist
      CompareFunc := CompareByArtist;
    sFolder: // by folder
      CompareFunc := CompareByFolder;
    sArtist2: // by artist2
      CompareFunc := CompareByArtist;
    sLanguage: // by Language
      CompareFunc := CompareByLanguage;
    sYear: // by Year
      CompareFunc := CompareByYear;
    sYearReversed: //by year reversed
      CompareFunc := CompareByYearReversed;
    sDecade: // by Decade
      CompareFunc := CompareByYear;
    else
      Log.LogCritical('Unsupported comparison', 'TSongs.Sort');
      Exit; // suppress warning
  end; // case

  // Note: Do not use TList.Sort() as it uses QuickSort which is instable.
  // For example, if a list is sorted by title first and
  // by artist afterwards, the songs of an artist will not be sorted by title anymore.
  // The stable MergeSort guarantees to maintain this order. 
  MergeSort(SongList, CompareFunc);
end;

procedure TCatSongs.SortSongs();
begin
  case TSortingType(Ini.Sorting) of
    sEdition: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sEdition);
      end;
    sGenre: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sGenre);
      end;
    sLanguage: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sLanguage);
      end;
    sFolder: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sFolder);
      end;
    sTitle: begin
        Songs.Sort(sTitle);
      end;
    sArtist: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
      end;
    sArtist2: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist2);
      end;
    sYear: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sYear);
      end;
    sYearReversed: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sYearReversed);
    end;
    sDecade: begin
        Songs.Sort(sTitle);
        Songs.Sort(sArtist);
        Songs.Sort(sYear);
      end;
  end; // case
end;

procedure TCatSongs.Refresh;
var I, J, K, Offset: integer; Item, Card: TSong;
  Folders, Prefixes: TStringList; Caption: UTF8String;
begin
  CatNumShow := -1;
  SortSongs;
  // Category objects belong to this view, real songs belong to Songs.SongList.
  for I := 0 to High(Song) do if Song[I].Main then Song[I].Free;
  SetLength(Song, 0);
  Folders := TStringList.Create;
  Prefixes := TStringList.Create;
  try
    Folders.Sorted := true; Folders.CaseSensitive := true;
    for I := 0 to Songs.SongList.Count - 1 do
    begin
      Item := TSong(Songs.SongList[I]);
      Prefixes.Clear;
      AddFolderChoices(Item.FolderPath, Ini.FolderDisplay, Prefixes);
      for J := 0 to Prefixes.Count - 1 do
      begin
        K := Folders.IndexOf(Prefixes[J]);
        if K < 0 then Folders.AddObject(Prefixes[J], TObject(PtrInt(1)))
        else Folders.Objects[K] := TObject(PtrInt(Folders.Objects[K]) + 1);
      end;
    end;
    Offset := Folders.Count; CatCount := Offset;
    SetLength(Song, Offset + Songs.SongList.Count);
    for I := 0 to Offset - 1 do
    begin
      Card := TSong.Create;
      Card.Main := true; Card.Visible := true;
      Card.FolderPath := Folders[I];
      Caption := Copy(Folders[I], 2, Length(Folders[I]) - 2);
      if Caption = '' then Caption := Language.Translate('SONG_JUMPTO_TYPE1');
      Card.Artist := '[' + Caption + ']';
      Card.OrderNum := I + 1;
      Card.CatNumber := PtrInt(Folders.Objects[I]);
      if Folders[I] = '/' then Card.CatNumber := Songs.SongList.Count;
      if CatCovers.CoverExists(sFolder, Folders[I]) then
        Card.Cover := CatCovers.GetCover(sFolder, Folders[I])
      else if CatCovers.CoverExists(sFolder, Caption) then
        Card.Cover := CatCovers.GetCover(sFolder, Caption)
      else
        Card.Cover := CatCovers.GetCover(sFolder, Copy(Caption, 1, Pos('/', Caption + '/') - 1));
      Song[I] := Card;
    end;
    for I := 0 to Songs.SongList.Count - 1 do
    begin
      Item := TSong(Songs.SongList[I]); Song[Offset + I] := Item;
      Item.Main := false; Item.Visible := Ini.FolderDisplay = 0;
      Item.OrderNum := 0; Item.CatNumber := I + 1;
    end;
  finally Prefixes.Free; Folders.Free; end;
  ResetVisibleIndexCache;
end;

procedure TCatSongs.ShowCategory(Index: integer);
var I: integer;
begin
  for I := 0 to High(Song) do
    if Song[I].Main and (Song[I].OrderNum = Index) then
    begin
      ScreenSongJumpto.SetFolderFilter(Song[I].FolderPath);
      Exit;
    end;
end;

procedure TCatSongs.HideCategory(Index: integer); // hides all songs in category
var
  S: integer; // song
begin
  for S := 0 to high(CatSongs.Song) do
  begin
    if not CatSongs.Song[S].Main then
      CatSongs.Song[S].Visible := false // hides all at now
  end;
  ResetVisibleIndexCache;
end;

procedure TCatSongs.ClickCategoryButton(Index: integer);
var
  Num: integer;
begin
  Num := CatSongs.Song[Index].OrderNum;
  if Num <> CatNumShow then
  begin
    ShowCategory(Num);
  end
  else
  begin
    ShowCategoryList;
  end;
end;

//Hide Categorys when in Category Hack
procedure TCatSongs.ShowCategoryList;
var
  S: integer;
begin
  // Hide All Songs Show All Cats
  for S := 0 to high(CatSongs.Song) do
    CatSongs.Song[S].Visible := CatSongs.Song[S].Main = (Ini.FolderDisplay > 0);
  CatSongs.Selected := CatNumShow; //Show last shown Category
  CatNumShow := -1;
  ResetVisibleIndexCache;
end;
//Hide Categorys when in Category Hack End

procedure TCatSongs.ResetVisibleIndexCache;
begin
  LastVisChecked := 0;
  LastVisIndex := 0;

  if Length(Song) > 0 then
    Song[0].VisibleIndex := 0;
end;

// Wrong song selected when tabs on bug
function TCatSongs.FindNextVisible(SearchFrom:integer): integer;// Find next Visible Song
var
  I: integer;
begin
  Result := -1;
  I := SearchFrom;
  while (Result = -1) do
  begin
    Inc (I);

    if (I > High(CatSongs.Song)) then
      I := Low(CatSongs.Song);

    if (I = SearchFrom) then // Make One Round and no song found->quit
      Break;

    if (CatSongs.Song[I].Visible) then
      Result := I;
  end;
end;

function TCatSongs.FindPreviousVisible(SearchFrom:integer): integer;// Find previous Visible Song
var
  I: integer;
begin
  Result := -1;
  I := SearchFrom;
  while (Result = -1) do
  begin
    Dec (I);

    if (I < Low(CatSongs.Song)) then
      I := High(CatSongs.Song);

    if (I = SearchFrom) then // Make One Round and no song found->quit
      Break;

    if (CatSongs.Song[I].Visible) then
      Result := I;
  end;
end;

// Wrong song selected when tabs on bug End

(**
 * Returns the number of visible songs.
 *)
function TCatSongs.VisibleSongs: integer;
begin
  Result := VisibleIndex(High(Song));
  if Song[High(Song)].Visible then
    Inc(Result);
end;

(**
 * Returns the index of a song in the subset of all visible songs.
 * If all songs are visible, the result will be equal to the Index parameter. 
 *)
function TCatSongs.VisibleIndex(Index: integer): integer;
begin
  while LastVisChecked < Index do
  begin
    if Song[LastVisChecked].Visible then
      Inc(LastVisIndex);
    Inc(LastVisChecked);
    Song[LastVisChecked].VisibleIndex := LastVisIndex;
  end;
  Result := Song[Index].VisibleIndex;
end;

function TCatSongs.FilterMask(const Rows: TSongFilterRows; ExceptRow: integer): TSongFilterMask;
var Saved: TSongFilterMask; I, R, Category: integer;
begin
  Result := nil;
  // Nonempty SetFilter calls only change visibility. Never clear a filter here:
  // that path restores playlist order and rebuilds category objects.
  SetLength(Result, Length(Song));
  SetLength(Saved, Length(Song));
  Category := CatNumShow;
  for I := 0 to High(Song) do
  begin
    Saved[I] := Song[I].Visible;
    Result[I] := not Song[I].Main;
  end;
  try
    for R := 0 to High(Rows) do
      if (R <> ExceptRow) and (Trim(Rows[R].Query) <> '') then
      begin
        SetFilter(Rows[R].Query, Rows[R].Kind);
        for I := 0 to High(Song) do Result[I] := Result[I] and Song[I].Visible;
      end;
  finally
    for I := 0 to High(Song) do Song[I].Visible := Saved[I];
    CatNumShow := Category;
    ResetVisibleIndexCache;
  end;
end;

function TCatSongs.SetFilters(const Rows: TSongFilterRows): cardinal;
var I, R: integer; Mask: array of boolean; Active: boolean;
begin
  SetLength(Mask, Length(Song));
  for I := 0 to High(Mask) do Mask[I] := not Song[I].Main;
  Active := false;
  for R := 0 to High(Rows) do
    if Trim(Rows[R].Query) <> '' then
    begin
      Active := true;
      SetFilter(Rows[R].Query, Rows[R].Kind);
      for I := 0 to High(Mask) do Mask[I] := Mask[I] and Song[I].Visible;
    end;
  if not Active then
  begin
    SetFilter('', fltAll);
    Exit(VisibleSongs);
  end;
  Result := 0;
  for I := 0 to High(Mask) do
  begin
    Song[I].Visible := Mask[I];
    if Mask[I] then Inc(Result);
  end;
  CatNumShow := -2;
  ResetVisibleIndexCache;
end;

function TCatSongs.SetFilter(FilterStr: UTF8String; Filter: TSongFilter): cardinal;
var
  I, J:      integer;
  TmpString: UTF8String;
  WordArray: array of UTF8String;
  FilterCopy: UTF8String;
  AgeParts: TStringList;
  AgeQuery, AgeRegion: string;
  RegionSeparator: integer;
  AgeTerms: array of record
    Region: string;
    Unrated, Valid: boolean;
    Condition: TAgeCondition;
  end;

  function MatchesAgeCondition(SongAge: integer; const Condition: TAgeCondition): boolean;
  begin
    if SongAge < 0 then Exit(false);

    case Condition.Comparator of
      acEqual:           Result := SongAge = Condition.Value;
      acLess:            Result := SongAge < Condition.Value;
      acLessOrEqual:     Result := SongAge <= Condition.Value;
      acGreater:         Result := SongAge > Condition.Value;
      acGreaterOrEqual:  Result := SongAge >= Condition.Value;
    else
      Result := false;
    end;
  end;
begin
    if Assigned(PlayListMan) then
    begin
      if (Filter = fltAll) and (Trim(FilterStr) = '') then
        PlayListMan.RestoreSongOrder;
    end;

  if (Filter = fltFolder) and (Trim(FilterStr) <> '') then
  begin
    Result := 0;
    for I := 0 to High(Song) do
    begin
      Song[I].Visible := not Song[I].Main and MatchesFolderPath(Song[I].FolderPath, FilterStr);
      if Song[I].Visible then Inc(Result);
    end;
    CatNumShow := -2; ResetVisibleIndexCache; Exit;
  end;

  FilterStr := Trim(LowerCase(TransliterateToASCII(FilterStr)));
  FilterCopy := FilterStr;
  if (Filter = fltAge) and (FilterCopy <> '') then
  begin
    AgeParts := TStringList.Create;
    try
      AgeParts.StrictDelimiter := true;
      AgeParts.QuoteChar := #0;
      AgeParts.Delimiter := ',';
      AgeParts.DelimitedText := StringReplace(FilterCopy, ';', ',', [rfReplaceAll]);
      SetLength(AgeTerms, AgeParts.Count);
      for I := 0 to AgeParts.Count - 1 do
      begin
        AgeQuery := Trim(AgeParts[I]);
        AgeRegion := Ini.AgeCountry;
        RegionSeparator := Pos(':', AgeQuery);
        if RegionSeparator > 0 then
        begin
          AgeRegion := UpperCase(Trim(Copy(AgeQuery, 1, RegionSeparator - 1)));
          Delete(AgeQuery, 1, RegionSeparator);
          AgeQuery := Trim(AgeQuery);
        end;
        AgeTerms[I].Region := AgeRegion;
        AgeTerms[I].Unrated := AgeQuery = '?';
        AgeTerms[I].Valid := ParseAgeCondition(AgeQuery, AgeTerms[I].Condition);
      end;
    finally AgeParts.Free; end;
  end;

  if (FilterStr <> '') then
  begin
    Result := 0;

    // initialize word array
    SetLength(WordArray, 1);

    // Copy words to SearchStr
    I := Pos(' ', FilterStr);
    while (I <> 0) do
    begin
      WordArray[High(WordArray)] := Copy(FilterStr, 1, I-1);
      SetLength(WordArray, Length(WordArray) + 1);

      FilterStr := TrimLeft(Copy(FilterStr, I+1, Length(FilterStr)-I));
      I := Pos(' ', FilterStr);
    end;

    // Copy last word
    WordArray[High(WordArray)] := FilterStr;

    for I := 0 to High(Song) do
    begin
      if Song[i].Main then
      begin
        Song[i].Visible := false;
        Continue;
      end;

      if Filter = fltAge then
      begin
        Song[I].Visible := false;
        for J := 0 to High(AgeTerms) do
        begin
          if AgeTerms[J].Unrated then
            Song[I].Visible := AgeForRegion(Song[I].AgeRaw, AgeTerms[J].Region) < 0
          else
            Song[I].Visible := AgeTerms[J].Valid and MatchesAgeCondition(
              AgeForRegion(Song[I].AgeRaw, AgeTerms[J].Region), AgeTerms[J].Condition);
          if Song[I].Visible then Break;
        end;
        if Song[i].Visible then
          Inc(Result);
        Continue;
      end;

      case Filter of
        fltAll:
          TmpString := Song[I].ArtistASCII + ' ' + Song[i].TitleASCII + ' ' + Song[i].LanguageASCII + ' ' + Song[i].EditionASCII + ' ' + Song[i].GenreASCII + ' ' + IntToStr(Song[i].Year) + ' ' + Song[i].CreatorASCII + ' ' + Song[i].TagsASCII; //+ ' ' + Song[i].Folder;
        fltTitle:
          TmpString := Song[I].TitleASCII;
        fltArtist:
          TmpString := Song[I].ArtistASCII;
        fltLanguage:
          TmpString := Song[I].LanguageASCII;
        fltEdition:
          TmpString := Song[I].EditionASCII;
        fltGenre:
          TmpString := Song[I].GenreASCII;
        fltYear:
          TmpString := IntToStr(Song[I].Year);
        fltCreator:
          TmpString := Song[I].CreatorASCII;
        fltTags:
          TmpString := Song[i].TagsASCII;
      end;

      if Filter in [fltTitle, fltArtist, fltLanguage, fltEdition, fltGenre, fltYear, fltCreator, fltTags] then
      begin
        Song[I].Visible := MatchesFilterTerms(TmpString, FilterCopy, Filter = fltYear);
        if Song[I].Visible then Inc(Result);
        Continue;
      end;
      Song[i].Visible := true;
      // Look for every searched word
      for J := 0 to High(WordArray) do
      begin
        Song[i].Visible := Song[i].Visible and
                           UTF8ContainsStr(TmpString, WordArray[J])
      end;
      if Song[i].Visible then
        Inc(Result);
    end;
    CatNumShow := -2;
  end
  else
  begin
    for i := 0 to High(Song) do
    begin
      Song[i].Visible := (Ini.Tabs = 1) = Song[i].Main;
      CatNumShow := -1;
    end;
    Result := 0;
  end;
  ResetVisibleIndexCache;
end;

// -----------------------------------------------------------------------------

end.
