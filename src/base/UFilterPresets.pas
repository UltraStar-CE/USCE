unit UFilterPresets;
{$mode delphi}{$codepage utf8}
interface
uses USongs, UPath, fpjson;
type
  TFilterPresetNames = array of UTF8String;
  TFilterPresets = class
  private
    FFile: IPath;
    FData: TJSONObject;
    procedure WriteData(Data: TJSONObject);
  public
    constructor Create(const Filename: IPath);
    destructor Destroy; override;
    function Names: TFilterPresetNames;
    function Contains(const Name: UTF8String): boolean;
    function Load(const Name: UTF8String): TSongFilterRows;
    procedure Save(const Name: UTF8String; const Rows: TSongFilterRows);
    procedure Delete(const Name: UTF8String);
  end;
implementation
uses Classes, SysUtils, jsonparser;
constructor TFilterPresets.Create(const Filename: IPath);
var Stream: TBinaryFileStream; Data: TJSONData;
begin
  inherited Create;
  FFile := Filename;
  if not FFile.Exists then begin FData := TJSONObject.Create; Exit; end;
  Stream := TBinaryFileStream.Create(FFile, fmOpenRead or fmShareDenyWrite);
  try Data := GetJSON(Stream); finally Stream.Free; end;
  if not (Data is TJSONObject) then begin Data.Free; raise Exception.Create('Invalid filter presets'); end;
  FData := TJSONObject(Data);
end;
destructor TFilterPresets.Destroy;
begin FData.Free; inherited; end;
function TFilterPresets.Names: TFilterPresetNames;
var I: integer;
begin
  Result := nil;
  SetLength(Result, FData.Count);
  for I := 0 to FData.Count - 1 do Result[I] := FData.Names[I];
end;
function TFilterPresets.Contains(const Name: UTF8String): boolean;
begin Result := FData.IndexOfName(Name) >= 0; end;
function TFilterPresets.Load(const Name: UTF8String): TSongFilterRows;
var Data, Kind, Query: TJSONData; Rows: TJSONArray; I, K: integer;
begin
  Result := nil;
  Data := FData.Find(Name);
  if not (Data is TJSONArray) then raise Exception.Create('Filter preset not found: ' + Name);
  Rows := TJSONArray(Data);
  if (Rows.Count < 1) or (Rows.Count > 256) then raise Exception.Create('Invalid filter row count');
  SetLength(Result, Rows.Count);
  for I := 0 to Rows.Count - 1 do
  begin
    if not (Rows[I] is TJSONObject) then raise Exception.Create('Invalid filter row');
    Kind := TJSONObject(Rows[I]).Find('kind');
    Query := TJSONObject(Rows[I]).Find('query');
    if (Kind = nil) or (Kind.JSONType <> jtNumber) or (Query = nil) or
       (Query.JSONType <> jtString) then raise Exception.Create('Invalid filter row');
    K := Kind.AsInteger;
    if (K < Ord(Low(TSongFilter))) or (K > Ord(High(TSongFilter))) then
      raise Exception.Create('Unknown filter type');
    Result[I].Kind := TSongFilter(K);
    Result[I].Query := Query.AsString;
  end;
end;
procedure TFilterPresets.WriteData(Data: TJSONObject);
var Temp, Backup: IPath; Stream: TBinaryFileStream; Text: UTF8String; HadFile: boolean;
begin
  Temp := Path(FFile.ToUTF8 + '.tmp');
  Backup := Path(FFile.ToUTF8 + '.bak');
  Text := Data.FormatJSON;
  Stream := TBinaryFileStream.Create(Temp, fmCreate);
  try if Text <> '' then Stream.WriteBuffer(Text[1], Length(Text)); finally Stream.Free; end;
  HadFile := FFile.Exists;
  if HadFile then
  begin
    if Backup.Exists then Backup.DeleteFile;
    if not FFile.Rename(Backup) then raise Exception.Create('Could not back up filter presets');
  end;
  if not Temp.Rename(FFile) then
  begin
    if HadFile then Backup.Rename(FFile);
    raise Exception.Create('Could not save filter presets');
  end;
  if HadFile then Backup.DeleteFile;
end;
procedure TFilterPresets.Save(const Name: UTF8String; const Rows: TSongFilterRows);
var Data: TJSONObject; Values: TJSONArray; I: integer;
begin
  if (Trim(Name) = '') or (Length(Rows) = 0) or (Length(Rows) > 256) then
    raise Exception.Create('A name and at least one filter row are required');
  Data := TJSONObject(FData.Clone);
  try
    Data.Delete(Name);
    Values := TJSONArray.Create;
    Data.Add(Name, Values);
    for I := 0 to High(Rows) do
      Values.Add(TJSONObject.Create(['kind', Ord(Rows[I].Kind), 'query', Rows[I].Query]));
    WriteData(Data);
    FreeAndNil(FData); FData := Data; Data := nil;
  finally Data.Free; end;
end;
procedure TFilterPresets.Delete(const Name: UTF8String);
var Data: TJSONObject;
begin
  Data := TJSONObject(FData.Clone);
  try
    Data.Delete(Name);
    WriteData(Data);
    FreeAndNil(FData); FData := Data; Data := nil;
  finally Data.Free; end;
end;
end.
