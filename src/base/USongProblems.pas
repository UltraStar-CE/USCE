unit USongProblems;
{$mode Delphi}{$codepage utf8}
interface
uses Classes, UPath;
type
  TSongProblems = class
  private
    FFile: IPath;
    FAvailable: boolean;
    FPaths: TStringList;
    procedure Save(Paths: TStringList);
  public
    constructor Create(const FileName: IPath);
    destructor Destroy; override;
    property Available: boolean read FAvailable;
    function IsFlagged(const SongFile: IPath): boolean;
    procedure Toggle(const SongFile: IPath);
  end;
function GetSongProblems: TSongProblems;
implementation
uses SysUtils, fpjson, jsonparser, UPlatform, ULog;
var SharedProblems: TSongProblems;
function GetSongProblems: TSongProblems;
begin
  if SharedProblems = nil then
    SharedProblems := TSongProblems.Create(Platform.GetGameUserPath.Append('song-problems.json'));
  Result := SharedProblems;
end;
constructor TSongProblems.Create(const FileName: IPath);
var Stream: TBinaryFileStream; Data: TJSONData; I: integer;
begin
  inherited Create;
  FFile := FileName;
  FPaths := TStringList.Create;
  {$IFDEF MSWINDOWS}FPaths.CaseSensitive := false;{$ELSE}FPaths.CaseSensitive := true;{$ENDIF}
  FPaths.Sorted := true;
  FPaths.Duplicates := dupIgnore;
  FAvailable := true;
  try
  if not FFile.Exists then Exit;
  Stream := TBinaryFileStream.Create(FFile, fmOpenRead or fmShareDenyWrite);
  try Data := GetJSON(Stream); finally Stream.Free; end;
  try
    if not (Data is TJSONArray) then raise Exception.Create('Invalid song problem flags');
    for I := 0 to Data.Count - 1 do
    begin
      if Data.Items[I].JSONType <> jtString then raise Exception.Create('Invalid song problem path');
      FPaths.Add(Data.Items[I].AsString);
    end;
  finally Data.Free; end;
  except
    on E: Exception do
    begin
      FAvailable := false;
      FPaths.Clear;
      if Assigned(Log) then Log.LogError(E.Message, 'SongProblems');
    end;
  end;
end;
destructor TSongProblems.Destroy;
begin FPaths.Free; inherited; end;
function TSongProblems.IsFlagged(const SongFile: IPath): boolean;
begin Result := (SongFile <> nil) and (FPaths.IndexOf(SongFile.ToUTF8) >= 0); end;
procedure TSongProblems.Save(Paths: TStringList);
var Data: TJSONArray; I: integer; Text: UTF8String;
    Temp, Backup: IPath; Stream: TBinaryFileStream; HadFile: boolean;
begin
  Data := TJSONArray.Create;
  try
    for I := 0 to Paths.Count - 1 do Data.Add(Paths[I]);
    Text := Data.AsJSON;
  finally Data.Free; end;
  Temp := Path(FFile.ToUTF8 + '.tmp');
  Backup := Path(FFile.ToUTF8 + '.bak');
  Stream := TBinaryFileStream.Create(Temp, fmCreate);
  try if Text <> '' then Stream.WriteBuffer(Text[1], Length(Text)); finally Stream.Free; end;
  HadFile := FFile.Exists;
  if HadFile then
  begin
    if Backup.Exists then Backup.DeleteFile;
    if not FFile.Rename(Backup) then raise Exception.Create('Could not back up song problem flags');
  end;
  if not Temp.Rename(FFile) then
  begin
    if HadFile then Backup.Rename(FFile);
    raise Exception.Create('Could not save song problem flags');
  end;
  if HadFile then Backup.DeleteFile;
end;
procedure TSongProblems.Toggle(const SongFile: IPath);
var Updated: TStringList; Index: integer;
begin
  if not FAvailable then raise Exception.Create('Song problem flags are unavailable');
  if (SongFile = nil) or SongFile.IsUnset then Exit;
  Updated := TStringList.Create;
  try
    Updated.CaseSensitive := FPaths.CaseSensitive;
    Updated.Assign(FPaths);
    Index := Updated.IndexOf(SongFile.ToUTF8);
    if Index < 0 then Updated.Add(SongFile.ToUTF8) else Updated.Delete(Index);
    Save(Updated);
    FPaths.Assign(Updated);
  finally Updated.Free; end;
end;
finalization
  SharedProblems.Free;
end.
