{ Game-owned song metadata snapshot. No frontend or transport dependencies.
  Callers own access policy and forwarding destinations. Single-thread owned. }
unit URemoteSongSnapshot;
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface
uses SysUtils, fpjson, sha1;
type
  TRemoteSongSnapshot = class
  private
    FSongs: TJSONArray;
    FId: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Replace(Songs: TJSONArray);
    function Chunk(Offset, Limit: integer): TJSONArray;
    function Count: integer;
    function IdentityForSong(SongId: integer): string;
    function Query(Request: TJSONObject): TJSONObject;
    property Id: string read FId;
  end;
implementation
function TRemoteSongSnapshot.IdentityForSong(SongId: integer): string;
var I: integer;
begin
  Result := '';
  for I := 0 to FSongs.Count - 1 do
    if FSongs.Objects[I].Get('songId', -1) = SongId then
      Exit(FSongs.Objects[I].Get('catalogKey', ''));
end;

procedure Sanitize(Data: TJSONData);
var I: integer; Obj: TJSONObject; Key: string;
begin
  if Data.JSONType = jtObject then
  begin
    Obj := TJSONObject(Data);
    for I := Obj.Count - 1 downto 0 do
    begin
      Key := Obj.Names[I];
      if (Key = 'audioPath') or (Key = 'coverPath') or
         (Key = 'txtPath') or (Key = 'filePath') or (Key = 'hostToken') then
        Obj.Delete(I)
      else Sanitize(Obj.Items[I]);
    end;
  end
  else if Data.JSONType = jtArray then
    for I := 0 to Data.Count - 1 do Sanitize(Data.Items[I]);
end;
constructor TRemoteSongSnapshot.Create;
begin
  inherited;
  FSongs := TJSONArray.Create;
  FId := SHA1Print(SHA1String('schema:4:[]'));
end;
destructor TRemoteSongSnapshot.Destroy;
begin
  FSongs.Free;
  inherited;
end;
procedure TRemoteSongSnapshot.Replace(Songs: TJSONArray);
var Next: TJSONArray; NextId: string;
begin
  Next := TJSONArray(Songs.Clone);
  try
    Sanitize(Next);
    NextId := SHA1Print(SHA1String('schema:4:' + Next.AsJSON));
  except
    Next.Free;
    raise;
  end;
  FSongs.Free;
  FSongs := Next;
  FId := NextId;
end;
function TRemoteSongSnapshot.Count: integer;
begin Result := FSongs.Count; end;
function TRemoteSongSnapshot.Chunk(Offset, Limit: integer): TJSONArray;
var I, Last: integer;
begin
  Result := TJSONArray.Create;
  if (Offset < 0) or (Limit <= 0) or (Offset >= Count) then Exit;
  if Limit > 100 then Limit := 100;
  Last := Offset + Limit - 1;
  if Last >= Count then Last := Count - 1;
  for I := Offset to Last do Result.Add(FSongs.Items[I].Clone);
end;
function TRemoteSongSnapshot.Query(Request: TJSONObject): TJSONObject;
var Offset, Limit: integer; Expected: string; Value: TJSONData;
begin
  Result := TJSONObject.Create(['snapshotId', FId, 'total', Count]);
  Value := Request.Find('offset');
  if (Value <> nil) and ((Value.JSONType <> jtNumber) or
    (Value.AsFloat < 0) or (Value.AsFloat > MaxInt) or
    (Frac(Value.AsFloat) <> 0)) then
  begin Result.Add('error', 'invalid_page'); Exit; end;
  Value := Request.Find('limit');
  if (Value <> nil) and ((Value.JSONType <> jtNumber) or
    (Value.AsFloat < 1) or (Value.AsFloat > 100) or
    (Frac(Value.AsFloat) <> 0)) then
  begin Result.Add('error', 'invalid_page'); Exit; end;
  Value := Request.Find('snapshotId');
  if (Value <> nil) and (Value.JSONType <> jtString) then
  begin Result.Add('error', 'invalid_snapshot'); Exit; end;
  Expected := Request.Get('snapshotId', '');
  Offset := Request.Get('offset', 0);
  Limit := Request.Get('limit', 100);
  if (Expected <> '') and (Expected <> FId) then
  begin
    Result.Add('error', 'snapshot_changed');
    Exit;
  end;
  if (Offset < 0) or (Limit < 1) or (Limit > 100) then
  begin
    Result.Add('error', 'invalid_page');
    Exit;
  end;
  Result.Add('offset', Offset);
  Result.Add('limit', Limit);
  Result.Add('songs', Chunk(Offset, Limit));
end;
end.
