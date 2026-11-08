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
    FPort: integer;
  protected
    procedure Execute; override;
  public
    Operation: TSyncerOperation;
    Songs: TSyncerSongs;
    ResponseCode: integer;
    Succeeded: boolean;
    constructor Create(Kind: TSyncerOperation; const Query: UTF8String; SongID: Int64);
    class function Enabled: boolean; static;
    class function ChartID(const Folder, Chart: IPath): Int64; static;
  end;

implementation

uses SysUtils, Sockets, FPHTTPClient, fpjson, jsonparser, UFilesystem, UIni, ULibraryLockdown;

type
  TResponseBuffer = class(TMemoryStream)
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

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
  URL, Status, Host: string;
  I, Count: integer;
  Deadline, NextPoll: QWord;

  function FindSyncer(const Host: string): boolean;
  var Page: string;
  begin
    FAddress := Host + ':' + IntToStr(FPort);
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
    if not FindSyncer('127.0.0.1') then
    begin
      Host := LocalIPv4;
      if (Host = '') or (Host = '127.0.0.1') or not FindSyncer(Host) then Exit;
    end;
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
          if (Txt is TJSONObject) and (TJSONObject(Txt).Get('fname', '') = Chart.ToUTF8) then
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
