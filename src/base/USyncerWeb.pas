unit USyncerWeb;

{$mode Delphi}{$H+}

interface

uses Classes, UPath;

type
  TSyncerSong = record
    ID: Int64;
    Artist, Title: UTF8String;
  end;
  TSyncerSongs = array of TSyncerSong;
  TSyncerOperation = (soSearch, soDownload);

  TSyncerClient = class(TThread)
  private
    FAddress, FQuery: UTF8String;
    FSongID: Int64;
    FPort, FLastPort: integer;
  protected
    procedure Execute; override;
  public
    Operation: TSyncerOperation;
    Songs: TSyncerSongs;
    ResponseCode: integer;
    Succeeded: boolean;
    constructor Create(Kind: TSyncerOperation; const Query: UTF8String; SongID: Int64);
    class function Enabled: boolean; static;
    class function SongFolder: IPath; static;
    class function ChartID(const Folder, Chart: IPath): Int64; static;
  end;

implementation

uses SysUtils, Sockets, FPHTTPClient, fpjson, jsonparser, UFilesystem, UIni, ULibraryLockdown
  {$IFDEF WINDOWS}, Registry, Windows{$ENDIF}
  {$IFDEF DARWIN}, Process{$ENDIF};

type
  TResponseBuffer = class(TMemoryStream)
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

{$IFDEF WINDOWS}
type
  PTcpRow = ^TTcpRow;
  TTcpRow = record
    State, LocalAddress, LocalPort, RemoteAddress, RemotePort: DWORD;
  end;

function GetTcpTable(Table: Pointer; var Size: DWORD; Sort: BOOL): DWORD; stdcall;
  external 'iphlpapi.dll' name 'GetTcpTable';
{$ENDIF}

procedure ListListeningPorts(Ports: TStrings; const Host: string);
{$IFDEF WINDOWS}
const
  TcpListen = 2;
var
  Table: PDWORD;
  Row: PTcpRow;
  Size, Required, I: DWORD;
  HostAddress, LoopbackAddress: in_addr;
begin
  HostAddress := StrToNetAddr(Host);
  LoopbackAddress := StrToNetAddr('127.0.0.1');
  Size := 0;
  if GetTcpTable(nil, Size, false) <> ERROR_INSUFFICIENT_BUFFER then Exit;
  repeat
    Required := Size;
    GetMem(Table, Required);
    try
      case GetTcpTable(Table, Size, false) of
        NO_ERROR:
          begin
            Row := PTcpRow(PByte(Table) + SizeOf(DWORD));
            I := 0;
            while I < Table^ do
            begin
              if ((Row^.LocalAddress = 0) or
                  (Row^.LocalAddress = HostAddress.s_addr) or
                  (Row^.LocalAddress = LoopbackAddress.s_addr)) and
                 ((Row^.State = TcpListen) or
                  ((Row^.RemoteAddress = 0) and (Row^.RemotePort = 0))) then
                Ports.Add(Format('%.5d', [ntohs(Word(Row^.LocalPort))]));
              Inc(Row);
              Inc(I);
            end;
            Exit;
          end;
        ERROR_INSUFFICIENT_BUFFER: ;
        else Exit;
      end;
    finally
      FreeMem(Table);
    end;
  until Size <= Required;
end;
{$ELSE}
var
  Lines, Fields: TStringList;
  Line, Address: string;
  Port: integer;
  {$IFDEF LINUX}
  Table: TextFile;
  {$ENDIF}
begin
  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    {$IFDEF LINUX}
    if not FileExists('/proc/net/tcp') then Exit;
    AssignFile(Table, '/proc/net/tcp');
    Reset(Table);
    try
      while not EOF(Table) do
      begin
        ReadLn(Table, Line);
        Lines.Add(Line);
      end;
    finally
      CloseFile(Table);
    end;
    {$ENDIF}
    {$IFDEF DARWIN}
    if not RunCommand('/usr/sbin/netstat', ['-an', '-p', 'tcp'], Line) then Exit;
    Lines.Text := Line;
    {$ENDIF}
    for Line in Lines do
    begin
      ExtractStrings([' ', #9], [], PChar(Line), Fields);
      {$IFDEF LINUX}
      if (Fields.Count > 3) and (Fields[3] = '0A') then
      begin
        Address := Fields[1];
        Port := StrToIntDef('$' + Copy(Address, Pos(':', Address) + 1, MaxInt), 0);
        if Port > 0 then Ports.Add(Format('%.5d', [Port]));
      end;
      {$ENDIF}
      {$IFDEF DARWIN}
      if (Fields.Count > 5) and (Fields[0] = 'tcp4') and (Fields[5] = 'LISTEN') then
      begin
        Address := Fields[3];
        Port := StrToIntDef(Copy(Address, LastDelimiter('.', Address) + 1, MaxInt), 0);
        if Port > 0 then Ports.Add(Format('%.5d', [Port]));
      end;
      {$ENDIF}
      Fields.Clear;
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
end;
{$ENDIF}

function TResponseBuffer.Write(const Buffer; Count: Longint): Longint;
begin
  if Position + Count > 1048576 then raise EStreamError.Create('Syncer response too large');
  Result := inherited Write(Buffer, Count);
end;

function LocalIPv4: string;
var
  Socket: TSocket;
  Address: TInetSockAddr;
  Size: TSockLen;
begin
  Result := '';
  Socket := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if Socket = TSocket(-1) then Exit;
  try
    FillChar(Address, SizeOf(Address), 0);
    Address.sin_family := AF_INET;
    Address.sin_port := htons(1);
    Address.sin_addr := StrToNetAddr('10.255.255.255');
    // Use the OS route to find our own address, like Syncer does. UDP sends no data here.
    if fpConnect(Socket, @Address, SizeOf(Address)) <> 0 then Exit;
    Size := SizeOf(Address);
    if fpGetSockName(Socket, @Address, @Size) = 0 then
      Result := NetAddrToStr(Address.sin_addr);
  finally
    CloseSocket(Socket);
  end;
end;

class function TSyncerClient.Enabled: boolean;
begin
  Result := (Ini.ExternalSongSearch <> 0) and not LibraryLockdown.Active;
end;

function EncodeQuery(const Query: UTF8String): UTF8String;
var C: AnsiChar;
begin
  Result := '';
  for C in Query do
    if C in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.', '~'] then
      Result := Result + C
    else
      Result := Result + '%' + IntToHex(Ord(C), 2);
end;

constructor TSyncerClient.Create(Kind: TSyncerOperation; const Query: UTF8String; SongID: Int64);
begin
  inherited Create(true);
  FPort := Ini.SyncerPort;
  FLastPort := InterlockedExchangeAdd(Ini.SyncerLastPort, 0);
  FQuery := Query;
  FSongID := SongID;
  Operation := Kind;
  Start;
end;

procedure TSyncerClient.Execute;
var
  Client: TFPHTTPClient;
  Body: TResponseBuffer;
  Data: TJSONData;
  Item: TJSONObject;
  URL, Status: string;
  I, Count: integer;
  Deadline, NextPoll: QWord;

  function FindSyncer(const Host: string; Port: integer): boolean;
  var Page: string;
  begin
    FAddress := Host + ':' + IntToStr(Port);
    Body.Clear;
    try
      Client.Get('http://' + FAddress + '/?limit=0', Body);
      SetString(Page, PChar(Body.Memory), Body.Size);
      Result := (Pos('id="songs-table"', Page) > 0) and
        (Pos('name="search"', Page) > 0) and (Pos('"/api/songs/"', Page) > 0);
    except
      Result := false;
    end;
    Body.Clear;
  end;

  function Connect: boolean;
  var
    Host: string;
    Ports: TStringList;
    Port, Index: integer;

    function Probe(Port: integer): boolean;
    begin
      Result := not Terminated and (Port > 0) and (Port <= 65535) and
        (FindSyncer('127.0.0.1', Port) or
         ((Host <> '') and (Host <> '127.0.0.1') and FindSyncer(Host, Port)));
      if Result and (FPort = 0) then InterlockedExchange(Ini.SyncerLastPort, Port);
    end;

  begin
    Host := LocalIPv4;
    if FPort > 0 then Exit(Probe(FPort));
    if Probe(FLastPort) then Exit(true);

    // Auto asks the OS for a port. Probe actual listeners instead of guessing its range.
    Ports := TStringList.Create;
    try
      Ports.Sorted := true;
      Ports.Duplicates := dupIgnore;
      ListListeningPorts(Ports, Host);
      Client.ConnectTimeout := 250;
      Client.IOTimeout := 750;
      // Auto ports are usually high. Leave services on conventional ports until last.
      for Index := Ports.Count - 1 downto 0 do
      begin
        if Terminated then Break;
        Port := StrToInt(Ports[Index]);
        if (Port <> FLastPort) and Probe(Port) then Exit(true);
      end;
    finally
      Client.ConnectTimeout := 700;
      Client.IOTimeout := 1500;
      Ports.Free;
    end;
    Result := false;
  end;

  function DownloadStatus(Post: boolean): string;
  begin
    Body.Clear;
    if Post then Client.Post(URL, Body) else Client.Get(URL, Body);
    Body.Position := 0;
    Data := GetJSON(Body);
    if not (Data is TJSONObject) then Exit('');
    Result := TJSONObject(Data).Get('status', '');
    FreeAndNil(Data);
  end;

begin
  Client := TFPHTTPClient.Create(nil);
  Body := TResponseBuffer.Create;
  Data := nil;
  try
    Client.ConnectTimeout := 700;
    Client.IOTimeout := 1500;
    Client.AllowRedirect := false;
    if not Connect then Exit;
    URL := 'http://' + FAddress + '/api/songs';
    try
      if Operation = soDownload then
      begin
        URL := URL + '/' + IntToStr(FSongID) + '/download';
        Status := DownloadStatus(true);
        Deadline := GetTickCount64 + 300000;
        while not Terminated and (GetTickCount64 < Deadline) and
              ((Status = 'Pending') or (Status = 'Downloading')) do
        begin
          NextPoll := GetTickCount64 + 3000;
          while not Terminated and (GetTickCount64 < NextPoll) do Sleep(100);
          if Terminated then Exit;
          Status := DownloadStatus(false);
        end;
        Succeeded := Status = 'Synchronized';
        Exit;
      end;
      Client.Get(URL + '?limit=100&search=' + EncodeQuery(FQuery), Body);
      Body.Position := 0;
      Data := GetJSON(Body);
      if not (Data is TJSONArray) then Exit;
      SetLength(Songs, Data.Count);
      Count := 0;
      for I := 0 to Data.Count - 1 do
      begin
        if not (Data.Items[I] is TJSONObject) then Continue;
        Item := TJSONObject(Data.Items[I]);
        Songs[Count].ID := Item.Get('song_id', Int64(0));
        if Songs[Count].ID <= 0 then Continue;
        Songs[Count].Title := Item.Get('title', '');
        Songs[Count].Artist := Item.Get('artist', '');
        Inc(Count);
      end;
      SetLength(Songs, Count);
      Succeeded := true;
    except
      ResponseCode := Client.ResponseStatusCode;
    end;
  finally
    Data.Free;
    Body.Free;
    Client.Free;
  end;
end;

class function TSyncerClient.SongFolder: IPath;
{$IFDEF WINDOWS}
var Settings: TRegistry;
{$ENDIF}
begin
  Result := PATH_NONE;
  {$IFDEF WINDOWS}
  Settings := TRegistry.Create(KEY_READ);
  try
    Settings.RootKey := HKEY_CURRENT_USER;
    if Settings.OpenKeyReadOnly('Software\bohning\usdb_syncer') and Settings.ValueExists('song_dir') then
      Result := Path(UnicodeString(Settings.ReadString('song_dir')));
  finally
    Settings.Free;
  end;
  {$ENDIF}
end;

class function TSyncerClient.ChartID(const Folder, Chart: IPath): Int64;
var
  Iter: IFileIterator;
  Entry: TFileInfo;
  Data, Txt: TJSONData;
  Stream: TBinaryFileStream;
begin
  Result := 0;
  Iter := FileSystem.FileFind(Folder.Append('*.usdb'), 0);
  while Iter.HasNext do
  begin
    Entry := Iter.Next;
    try
      Stream := TBinaryFileStream.Create(Folder.Append(Entry.Name), fmOpenRead or fmShareDenyNone);
      try
        if Stream.Size > 65536 then Continue;
        Data := GetJSON(Stream);
        try
          if not (Data is TJSONObject) then Continue;
          Txt := TJSONObject(Data).Find('txt');
          if (Txt is TJSONObject) and
             Chart.Equals(UTF8String(TJSONObject(Txt).Get('fname', '')), not FileSystem.IsCaseSensitive) then
            Exit(TJSONObject(Data).Get('song_id', Int64(0)));
        finally
          Data.Free;
        end;
      finally
        Stream.Free;
      end;
    except
      // Syncer may be rewriting the metadata.
    end;
  end;
end;

end.
