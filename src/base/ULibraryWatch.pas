unit ULibraryWatch;
{$mode Delphi}{$H+}{$pointermath on}

interface

uses Classes, SysUtils;

type
  // Native notifications only. The worker never touches songs, menus or media.
  TLibraryWatch = class(TThread)
  private
    Roots, Pending: TStringList;
    {$IFDEF DARWIN}CanonicalRoots: TStringList;{$ENDIF}
    Lock: TRTLCriticalSection;
    Full: boolean;
    FirstChange, LastChange: QWord;
    ErrorText: string;
    procedure Changed(const Name: string);
    procedure ChangedEntry(const Name: string);
    procedure Recover;
    function Relevant(const Name: string): boolean;
    procedure RunNative;
  protected
    procedure Execute; override;
  public
    constructor Create(const Paths: TStrings);
    destructor Destroy; override;
    function TakeChanges(Paths: TStrings; out AllRoots: boolean; out Error: string): boolean;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}Windows{$ENDIF}
  {$IFDEF LINUX}BaseUnix, Linux{$ENDIF}
  {$IFDEF DARWIN}MacOSAll, FSEvents{$ENDIF};

type EWatchOverflow = class(Exception);

function Normal(const Name: string): string;
begin
  {$IFDEF MSWINDOWS}
  Result := UTF8Encode(UnicodeLowerCase(ExcludeTrailingPathDelimiter(ExpandFileName(UTF8Decode(Name)))));
  {$ELSE}
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Name));
  {$ENDIF}
end;

function Within(const Name, Parent: string): boolean;
begin
  Result := (Name = Parent) or (Pos(IncludeTrailingPathDelimiter(Parent), Name) = 1);
end;

constructor TLibraryWatch.Create(const Paths: TStrings);
var I: integer;
begin
  inherited Create(true);
  InitCriticalSection(Lock);
  Roots := TStringList.Create;
  Roots.CaseSensitive := true;
  Pending := TStringList.Create;
  Pending.CaseSensitive := true;
  {$IFDEF DARWIN}CanonicalRoots := TStringList.Create;{$ENDIF}
  for I := 0 to Paths.Count - 1 do
    if Roots.IndexOf(Normal(Paths[I])) < 0 then Roots.Add(Normal(Paths[I]));
  Start;
end;

destructor TLibraryWatch.Destroy;
begin
  Terminate;
  WaitFor;
  Pending.Free;
  {$IFDEF DARWIN}CanonicalRoots.Free;{$ENDIF}
  Roots.Free;
  DoneCriticalSection(Lock);
  inherited;
end;

function TLibraryWatch.Relevant(const Name: string): boolean;
var I: integer;
begin
  for I := 0 to Roots.Count - 1 do
    if Within(Name, Roots[I]) or Within(Roots[I], Name) then Exit(true);
  Result := false;
end;

procedure TLibraryWatch.Recover;
begin
  EnterCriticalSection(Lock);
  try
    Full := true;
    Pending.Clear;
    if FirstChange = 0 then FirstChange := GetTickCount64;
    LastChange := GetTickCount64;
  finally LeaveCriticalSection(Lock); end;
end;

procedure TLibraryWatch.Changed(const Name: string);
var N: string; I: integer;
begin
  N := Normal(Name);
  if not Relevant(N) then Exit;
  // Never scan an ancestor outside the configured library (e.g. root deletion).
  for I := 0 to Roots.Count - 1 do
    if (N <> Roots[I]) and Within(Roots[I], N) then
    begin Recover; Exit; end;
  EnterCriticalSection(Lock);
  try
    if FirstChange = 0 then FirstChange := GetTickCount64;
    LastChange := GetTickCount64;
    if Full then Exit;
    for I := Pending.Count - 1 downto 0 do
    begin
      if Within(N, Pending[I]) then Exit;
      if Within(Pending[I], N) then Pending.Delete(I);
    end;
    if Pending.Count >= 256 then
    begin Full := true; Pending.Clear; end
    else Pending.Add(N);
  finally LeaveCriticalSection(Lock); end;
end;

procedure TLibraryWatch.ChangedEntry(const Name: string);
begin
  if not Relevant(Normal(Name)) then Exit;
  // Existing TXT changes target just that header. New/moved directories target
  // only their subtree. Removals and media changes reconcile the containing song
  // folder, so a failed read is never mistaken for a deletion tombstone.
  {$IFDEF MSWINDOWS}
  if DirectoryExists(UTF8Decode(Name)) or
     (SameText(ExtractFileExt(Name), '.txt') and FileExists(UTF8Decode(Name))) then
  {$ELSE}
  if DirectoryExists(Name) or (SameText(ExtractFileExt(Name), '.txt') and FileExists(Name)) then
  {$ENDIF}
    Changed(Name)
  else Changed(ExtractFileDir(Name));
end;

function TLibraryWatch.TakeChanges(Paths: TStrings; out AllRoots: boolean; out Error: string): boolean;
var Now: QWord;
begin
  EnterCriticalSection(Lock);
  try
    Error := ErrorText;
    ErrorText := '';
    AllRoots := false;
    Now := GetTickCount64;
    Result := (FirstChange <> 0) and
      ((Now - LastChange >= 300) or (Now - FirstChange >= 2000));
    if not Result then Exit;
    AllRoots := Full;
    Paths.Assign(Pending);
    Pending.Clear;
    Full := false;
    FirstChange := 0;
  finally LeaveCriticalSection(Lock); end;
end;

procedure TLibraryWatch.Execute;
var Restart: boolean;
begin
  repeat
    Restart := false;
    try
      RunNative;
    except
      on E: EWatchOverflow do
      begin
        Recover;
        Restart := true; // recreate native watches before reconciliation
      end;
      on E: Exception do
      begin
        EnterCriticalSection(Lock);
        try ErrorText := E.ClassName + ': ' + E.Message;
        finally LeaveCriticalSection(Lock); end;
        // One recovery scan, not a polling loop when watching is unavailable.
        Recover;
      end;
    end;
  until Terminated or not Restart;
end;

{$IFDEF MSWINDOWS}
type
  TDirectoryWatch = class
    Name: string;
    Handle: THandle;
    Overlap: TOverlapped;
    Buffer: array[0..16383] of DWORD; // DWORD aligned, 64 KiB also works on shares.
    Recursive, PendingIO: boolean;
    destructor Destroy; override;
    procedure Arm;
  end;

destructor TDirectoryWatch.Destroy;
var Bytes: DWORD;
begin
  if Handle <> INVALID_HANDLE_VALUE then
  begin
    if PendingIO then
    begin
      CancelIo(Handle); // created and cancelled on this worker
      GetOverlappedResult(Handle, Overlap, Bytes, true);
    end;
    CloseHandle(Handle);
  end;
  if Overlap.hEvent <> 0 then CloseHandle(Overlap.hEvent);
  inherited;
end;

procedure TDirectoryWatch.Arm;
var Mask: DWORD;
begin
  ResetEvent(Overlap.hEvent);
  Mask := FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME;
  if Recursive then Mask := Mask or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE;
  if not ReadDirectoryChangesW(Handle, @Buffer, SizeOf(Buffer), Recursive,
    Mask, nil, @Overlap, nil) then
    RaiseLastOSError;
  PendingIO := true;
end;

procedure TLibraryWatch.RunNative;
var Watches: TList; I, J, Offset: integer; W: TDirectoryWatch;
  Bytes, Next, NameLength: DWORD; N: UnicodeString; Reopen: boolean; ResetRoots: TStringList;
procedure Add(const Name: string; Recursive: boolean);
var K: integer; Item: TDirectoryWatch;
begin
  for K := 0 to Watches.Count - 1 do
    if (TDirectoryWatch(Watches[K]).Name = Name) and
       (TDirectoryWatch(Watches[K]).Recursive = Recursive) then Exit;
  if not DirectoryExists(UTF8Decode(Name)) then Exit;
  Item := TDirectoryWatch.Create;
  Item.Handle := INVALID_HANDLE_VALUE;
  try
    Item.Name := Name;
    Item.Recursive := Recursive;
    Item.Handle := CreateFileW(PWideChar(UTF8Decode(Name)), FILE_LIST_DIRECTORY,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
    if Item.Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
    Item.Overlap.hEvent := CreateEvent(nil, true, false, nil);
    if Item.Overlap.hEvent = 0 then RaiseLastOSError;
    Item.Arm;
    Watches.Add(Item);
  except Item.Free; raise; end;
end;
begin
  Watches := TList.Create;
  ResetRoots := TStringList.Create;
  try
    for I := 0 to Roots.Count - 1 do
    begin
      Add(ExtractFileDir(Roots[I]), false); // root deletion/recreation
      Add(Roots[I], true);
    end;
    Recover; // close the startup enumeration/registration race
    while not Terminated do
    begin
      Reopen := false;
      ResetRoots.Clear;
      for I := Watches.Count - 1 downto 0 do
      begin
        W := TDirectoryWatch(Watches[I]);
        if WaitForSingleObject(W.Overlap.hEvent, 0) <> WAIT_OBJECT_0 then Continue;
        W.PendingIO := false;
        if not GetOverlappedResult(W.Handle, W.Overlap, Bytes, false) then
        begin
          Recover; Reopen := true;
          W.Free; Watches.Delete(I);
          Continue;
        end;
        if Bytes = 0 then Recover // native event buffer overflow
        else
        begin
          Offset := 0;
          repeat
            if Offset + 12 > integer(Bytes) then begin Recover; Break; end;
            Next := PDWORD(PByte(@W.Buffer) + Offset)^;
            NameLength := PDWORD(PByte(@W.Buffer) + Offset + 8)^;
            if (NameLength mod 2 <> 0) or (NameLength > Bytes - DWORD(Offset) - 12) then
            begin Recover; Break; end;
            SetString(N, PWideChar(PByte(@W.Buffer) + Offset + 12), NameLength div 2);
            N := UTF8Decode(IncludeTrailingPathDelimiter(W.Name)) + N;
            if Relevant(Normal(UTF8Encode(N))) then
            begin
              // A directory scan also handles removals and related media changes.
              ChangedEntry(UTF8Encode(N));
              for J := 0 to Roots.Count - 1 do
                if Normal(UTF8Encode(N)) = Roots[J] then
                begin
                  Recover; Reopen := true; ResetRoots.Add(Roots[J]);
                end;
            end;
            if Next = 0 then Break;
            if (Next < 12) or (Next > Bytes - DWORD(Offset)) then begin Recover; Break; end;
            Inc(Offset, Next);
          until false;
        end;
        try W.Arm;
        except
          Recover;
          W.Free; Watches.Delete(I);
        end;
      end;
      // A renamed directory handle follows the old inode, not the configured
      // pathname. Close it before watching a replacement at the original path.
      for I := Watches.Count - 1 downto 0 do
      begin
        W := TDirectoryWatch(Watches[I]);
        if W.Recursive and (ResetRoots.IndexOf(W.Name) >= 0) then
        begin W.Free; Watches.Delete(I); end;
      end;
      // Reopen roots only after a native event reports their recreation.
      if Reopen then for I := 0 to Roots.Count - 1 do Add(Roots[I], true);
      Sleep(50);
    end;
  finally
    for I := 0 to Watches.Count - 1 do TObject(Watches[I]).Free;
    Watches.Free;
    ResetRoots.Free;
  end;
end;
{$ENDIF}

{$IFDEF LINUX}
procedure TLibraryWatch.RunNative;
var FD, I, Count, Offset, Index, WD: integer; Dirs: TStringList;
  Buffer: array[0..65535] of byte; E: Pinotify_event; N, Parent: string;
procedure AddTree(const Name: string; Recursive: boolean);
var Search: TSearchRec; Code, Error: integer; Child: string;
begin
  if Terminated or not DirectoryExists(Name) then Exit;
  Index := Dirs.IndexOf(Name);
  if Index < 0 then
  begin
    WD := inotify_add_watch(FD, PChar(Name), IN_CREATE or IN_DELETE or IN_MOVED_FROM or
      IN_MOVED_TO or IN_CLOSE_WRITE or IN_ATTRIB or IN_DELETE_SELF or IN_MOVE_SELF or IN_ONLYDIR);
    if WD < 0 then RaiseLastOSError;
    Dirs.AddObject(Name, TObject(PtrInt(WD)));
  end;
  if not Recursive then Exit;
  fpSetErrno(0);
  Code := FindFirst(IncludeTrailingPathDelimiter(Name) + '*', faAnyFile, Search);
  Error := fpGetErrno;
  if Code <> 0 then
  begin
    if Error <> 0 then raise EOSError.Create('Cannot register song subdirectories: ' + Name);
    Exit;
  end;
  try
    repeat
      if (Search.Name <> '.') and (Search.Name <> '..') and
         ((Search.Attr and (faDirectory or faSymLink)) = faDirectory) then
      begin
        Child := IncludeTrailingPathDelimiter(Name) + Search.Name;
        AddTree(Child, true);
      end;
      fpSetErrno(0);
      Code := FindNext(Search);
      Error := fpGetErrno;
    until (Code <> 0) or Terminated;
    if not Terminated and (Error <> 0) then
      raise EOSError.Create('Cannot finish registering song subdirectories: ' + Name);
  finally FindClose(Search); end;
end;
begin
  FD := inotify_init;
  if FD < 0 then RaiseLastOSError;
  // FPC 3.2.2's x86 inotify_init1 wrapper calls inotify_init and loses flags.
  if (fpFcntl(FD, F_SETFL, O_NONBLOCK) < 0) or
     (fpFcntl(FD, F_SETFD, 1 {FD_CLOEXEC}) < 0) then
  begin fpClose(FD); RaiseLastOSError; end;
  Dirs := TStringList.Create;
  Dirs.CaseSensitive := true;
  try
    for I := 0 to Roots.Count - 1 do
    begin
      AddTree(Roots[I], true);
      AddTree(ExtractFileDir(Roots[I]), false);
    end;
    Recover;
    while not Terminated do
    begin
      Count := fpRead(FD, Buffer, SizeOf(Buffer));
      if (Count < 0) and (fpGetErrno <> ESysEAGAIN) and (fpGetErrno <> ESysEINTR) then RaiseLastOSError;
      Offset := 0;
      while Offset + 16 <= Count do
      begin
        E := Pinotify_event(@Buffer[Offset]);
        if E^.len > cardinal(Count - Offset - 16) then begin Recover; Break; end;
        if (E^.mask and IN_Q_OVERFLOW) <> 0 then
          raise EWatchOverflow.Create('inotify queue overflow');
        Index := -1;
        for I := 0 to Dirs.Count - 1 do
          if PtrInt(Dirs.Objects[I]) = E^.wd then begin Index := I; Break; end;
        if Index >= 0 then
        begin
          Parent := Dirs[Index];
          if E^.len > 0 then N := IncludeTrailingPathDelimiter(Parent) + PChar(@E^.name)
          else N := Parent;
          if Relevant(N) then
          begin
            if E^.len > 0 then ChangedEntry(N)
            else if (E^.mask and IN_IGNORED) = 0 then Changed(ExtractFileDir(Parent));
            if (E^.mask and (IN_DELETE or IN_MOVED_FROM or IN_DELETE_SELF or IN_MOVE_SELF)) <> 0 then
            begin
              // Drop stale pathname mappings, including renamed subdirectories.
              for I := Dirs.Count - 1 downto 0 do
                if Within(Dirs[I], N) then
                begin inotify_rm_watch(FD, PtrInt(Dirs.Objects[I])); Dirs.Delete(I); end;
            end;
            if (E^.mask and IN_ISDIR <> 0) and (E^.mask and (IN_CREATE or IN_MOVED_TO) <> 0) then
              AddTree(N, true);
          end;
          if (E^.mask and IN_IGNORED <> 0) then
          begin
            Index := Dirs.IndexOf(Parent);
            if Index >= 0 then Dirs.Delete(Index);
          end;
        end;
        Inc(Offset, 16 + E^.len);
      end;
      if Count <= 0 then Sleep(50);
    end;
  finally Dirs.Free; fpClose(FD); end;
end;
{$ENDIF}

{$IFDEF DARWIN}
function NativeRealPath(Name, Buffer: PChar): PChar; cdecl; external 'c' name 'realpath';

procedure LibraryEvents(Stream: ConstFSEventStreamRef; Info: UnivPtr; Count: size_t;
  Paths: UnivPtr; Flags: FSEventStreamEventFlagsPtr; Ids: FSEventStreamEventIdPtr); mwpascal;
var I: size_t; J: integer; Names: PPChar; Watch: TLibraryWatch; N: string;
begin
  Watch := TLibraryWatch(Info);
  Names := PPChar(Paths);
  if Count = 0 then Exit;
  // Never allow Pascal exceptions to cross the C callback boundary.
  try
    for I := 0 to Count - 1 do
    begin
      if (Flags[I] and (kFSEventStreamEventFlagMustScanSubDirs or
        kFSEventStreamEventFlagUserDropped or kFSEventStreamEventFlagKernelDropped or
        kFSEventStreamEventFlagRootChanged)) <> 0 then Watch.Recover
      else
      begin
        N := Normal(Names[I]);
        for J := 0 to Watch.Roots.Count - 1 do
          if Within(N, Watch.CanonicalRoots[J]) then
          begin
            N := Watch.Roots[J] + Copy(N, Length(Watch.CanonicalRoots[J]) + 1, MaxInt);
            Watch.ChangedEntry(N);
            Break;
          end
          else if Within(Watch.CanonicalRoots[J], N) then Watch.Recover;
      end;
    end;
  except Watch.Recover; end;
end;

procedure TLibraryWatch.RunNative;
var Paths: CFMutableArrayRef; Text: CFStringRef; Context: FSEventStreamContext;
  Stream: FSEventStreamRef; I: integer; Buffer: array[0..4095] of char; Native: string;
begin
  Paths := CFArrayCreateMutable(nil, 0, @kCFTypeArrayCallBacks);
  if Paths = nil then raise Exception.Create('Cannot allocate FSEvents paths');
  try
    for I := 0 to Roots.Count - 1 do
    begin
      Native := Roots[I];
      if NativeRealPath(PChar(Native), @Buffer[0]) <> nil then Native := PChar(@Buffer[0]);
      CanonicalRoots.Add(Native);
      Text := CFStringCreateWithCString(nil, PChar(Native), kCFStringEncodingUTF8);
      if Text = nil then raise Exception.Create('Cannot encode FSEvents path');
      CFArrayAppendValue(Paths, Text); CFRelease(Text);
      Text := CFStringCreateWithCString(nil, PChar(ExtractFileDir(Native)), kCFStringEncodingUTF8);
      if Text = nil then raise Exception.Create('Cannot encode FSEvents parent path');
      CFArrayAppendValue(Paths, Text); CFRelease(Text);
    end;
    FillChar(Context, SizeOf(Context), 0); Context.info := Self;
    Stream := FSEventStreamCreate(nil, @LibraryEvents, @Context, Paths,
      kFSEventStreamEventIdSinceNow, 0.3,
      kFSEventStreamCreateFlagFileEvents or kFSEventStreamCreateFlagWatchRoot);
    if Stream = nil then raise Exception.Create('Cannot create FSEvents stream');
    try
      FSEventStreamScheduleWithRunLoop(Stream, CFRunLoopGetCurrent, kCFRunLoopDefaultMode);
      if not FSEventStreamStart(Stream) then raise Exception.Create('Cannot start FSEvents stream');
      try
        Recover;
        while not Terminated do CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
      finally FSEventStreamStop(Stream); end;
    finally FSEventStreamInvalidate(Stream); FSEventStreamRelease(Stream); end;
  finally CFRelease(Paths); end;
end;
{$ENDIF}
end.
