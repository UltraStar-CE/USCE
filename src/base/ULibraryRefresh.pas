unit ULibraryRefresh;
{$mode Delphi}
interface
uses Classes, UPath, USong, UTextEncoding;
type
  // Owns staged headers until the main thread accepts them. No menus, audio or GPU.
  TLibraryRefresh = class(TThread)
  private
    Roots, FolderRoots, Skipped: TPathDynArray;
    procedure Scan(const Name: IPath);
    procedure ReadSong(const Name: IPath);
  protected
    procedure Execute; override;
  public
    Entries, Seen: TStringList;
    Failure, AgeCountry: UTF8String;
    DefaultEncoding: UTextEncoding.TEncoding;
    constructor Create(const Paths, LibraryRoots: TPathDynArray; Encoding: UTextEncoding.TEncoding; const Country: UTF8String);
    destructor Destroy; override;
    function Covers(const Name: IPath): boolean;
    class function Key(const Name: IPath): string; static;
  end;
implementation
uses SysUtils, UFilesystem, ULog, UUnicodeUtils,
  {$IFDEF MSWINDOWS}Windows{$ELSE}BaseUnix{$ENDIF};
procedure ClearSearchError;
begin
  {$IFDEF MSWINDOWS}SetLastError(0);{$ELSE}fpSetErrno(0);{$ENDIF}
end;
function SearchEnded(Code, Error: integer; Opening: boolean): boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := (Code = 18) or (Opening and (Code = 2)); // no more files / empty match
  {$ELSE}
  // FPC Unix returns -1 for both EOF and failure; errno distinguishes them.
  Result := (Code = -1) and (Error = 0);
  {$ENDIF}
end;
constructor TLibraryRefresh.Create(const Paths, LibraryRoots: TPathDynArray; Encoding: UTextEncoding.TEncoding; const Country: UTF8String);
begin
  inherited Create(true);
  DefaultEncoding := Encoding;
  AgeCountry := Country;
  Roots := Copy(Paths);
  FolderRoots := Copy(LibraryRoots);
  Entries := TStringList.Create;
  Entries.Sorted := true;
  Entries.CaseSensitive := true;
  Seen := TStringList.Create;
  Seen.Sorted := true;
  Seen.CaseSensitive := true;
  Start;
end;
destructor TLibraryRefresh.Destroy;
var I: integer;
begin
  Terminate;
  WaitFor;
  for I := 0 to Entries.Count - 1 do Entries.Objects[I].Free;
  Entries.Free;
  Seen.Free;
  inherited;
end;
class function TLibraryRefresh.Key(const Name: IPath): string;
begin
  Result := Name.GetAbsolutePath.ToUTF8;
  if not FileSystem.IsCaseSensitive then Result := UTF8LowerCase(Result);
end;
function TLibraryRefresh.Covers(const Name: IPath): boolean;
var I: integer;
begin
  for I := 0 to High(Skipped) do
    if (Key(Name) = Key(Skipped[I])) or Name.IsChildOf(Skipped[I], false) then Exit(false);
  for I := 0 to High(Roots) do
    if (Key(Name) = Key(Roots[I])) or Name.IsChildOf(Roots[I], false) then Exit(true);
  Result := false;
end;
procedure TLibraryRefresh.ReadSong(const Name: IPath);
var Song: TSong; Stream: TMemTextFileStream; Line, Last: UTF8String; I: integer;
begin
  if Seen.IndexOf(Key(Name)) >= 0 then Exit;
  Seen.Add(Key(Name));
  Song := nil;
  try
    Stream := TMemTextFileStream.Create(Name, fmOpenRead or fmShareDenyWrite);
    try
      Last := '';
      while Stream.ReadLine(Line) do
        if Trim(Line) <> '' then Last := Trim(Line);
      // Keep an existing header if an external writer has not finished this file.
      if Last <> 'E' then Exit;
      Stream.Position := 0;
      Song := TSong.Create;
      Song.Path := Name.GetPath;
      Song.FileName := Name.GetName;
      Song.Mult := 1;
      Song.Folder := 'Unknown';
      for I := 0 to High(FolderRoots) do
        if Name.IsChildOf(FolderRoots[I], false) then
        begin
          if Name.IsChildOf(FolderRoots[I], true) then Song.Folder := FolderRoots[I].RemovePathDelim.ToUTF8
          else Song.Folder := Name.GetRelativePath(FolderRoots[I].AppendPathDelim).SplitDirs[0].RemovePathDelim.ToUTF8;
          Break;
        end;
      if Song.ReadRefreshHeader(Stream, DefaultEncoding, AgeCountry) then
      begin
        Entries.AddObject(Key(Name), Song);
        Song := nil;
      end;
    finally
      Stream.Free;
    end;
  except
    on E: Exception do Log.LogError(Name.ToUTF8 + ': ' + E.Message, 'Library refresh');
  end;
  Song.Free;
end;
procedure TLibraryRefresh.Scan(const Name: IPath);
var Search: TSytemSearchRec; Entry, Child: IPath; Code, Error: integer;
begin
  if Terminated then Exit;
  if Name.IsFile then
  begin
    if Name.GetExtension.Equals('.txt', true) then ReadSong(Name);
    Exit;
  end;
  if not Name.IsDirectory then raise Exception.Create('Cannot scan ' + Name.ToUTF8);
  ClearSearchError;
  Code := FileSystem.FindFirst(Name.Append('*'), faAnyFile, Search);
  Error := GetLastOSError;
  if Code <> 0 then
  begin
    if SearchEnded(Code, Error, true) and Name.IsDirectory then Exit;
    raise Exception.Create('Cannot enumerate ' + Name.ToUTF8 + ' (OS error ' + IntToStr(Error) + ')');
  end;
  try
    while (Code = 0) and not Terminated do
    begin
      Entry := Path(Search.Name);
      if not Entry.Equals('.') and not Entry.Equals('..') then
      begin
        Child := Name.Append(Entry);
        if (Search.Attr and faSymLink) <> 0 then
        begin
          // Preserve aliases already followed by startup, without recursing cycles.
          SetLength(Skipped, Length(Skipped) + 1);
          Skipped[High(Skipped)] := Child;
        end
        else if (Search.Attr and faDirectory) <> 0 then Scan(Child)
        else if Child.GetExtension.Equals('.txt', true) then ReadSong(Child);
      end;
      ClearSearchError;
      Code := FileSystem.FindNext(Search);
      Error := GetLastOSError;
    end;
    if not Terminated and not SearchEnded(Code, Error, false) then
      raise Exception.Create('Cannot finish enumeration of ' + Name.ToUTF8 + ' (OS error ' + IntToStr(Error) + ')');
  finally
    FileSystem.FindClose(Search);
  end;
end;
procedure TLibraryRefresh.Execute;
var I: integer;
begin
  try
    for I := 0 to High(Roots) do Scan(Roots[I]);
  except
    on E: Exception do
    begin
      Failure := E.ClassName + ': ' + E.Message;
      LogWorkerException('TLibraryRefresh.Execute');
    end;
  end;
end;
end.
