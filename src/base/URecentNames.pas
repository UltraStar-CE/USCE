unit URecentNames;

{$mode delphi}

interface

uses SysUtils, IniFiles;

type TRecentNames = array of UTF8String;
const MaxRecentNames = 256;

procedure RememberRecentName(var Names: TRecentNames; const Value: UTF8String);
function PredictRecentName(const Names: TRecentNames; const Prefix: UTF8String): UTF8String;
function LoadRecentNames(Ini: TCustomIniFile): TRecentNames;
procedure SaveRecentNames(Ini: TCustomIniFile; const Names: TRecentNames);

implementation

procedure RememberRecentName(var Names: TRecentNames; const Value: UTF8String);
var Name: UTF8String; I, J: integer;
begin
  Name := Trim(Value);
  if (Name = '') or (Pos(#10, Name) > 0) or (Pos(#13, Name) > 0) then Exit;
  for I := 0 to High(Names) do
    if WideCompareText(UTF8Decode(Names[I]), UTF8Decode(Name)) = 0 then
    begin
      for J := I to High(Names) - 1 do Names[J] := Names[J + 1];
      SetLength(Names, Length(Names) - 1);
      Break;
    end;
  if Length(Names) < MaxRecentNames then SetLength(Names, Length(Names) + 1);
  for I := High(Names) downto 1 do Names[I] := Names[I - 1];
  Names[0] := Name;
end;

function PredictRecentName(const Names: TRecentNames; const Prefix: UTF8String): UTF8String;
var I: integer; WidePrefix, WideName: UnicodeString;
begin
  Result := '';
  if Prefix = '' then Exit;
  WidePrefix := UTF8Decode(Prefix);
  for I := 0 to High(Names) do
  begin
    WideName := UTF8Decode(Names[I]);
    if (Length(WideName) >= Length(WidePrefix)) and
      (WideCompareText(Copy(WideName, 1, Length(WidePrefix)), WidePrefix) = 0) then
    begin
      if Length(WideName) > Length(WidePrefix) then Result := Names[I];
      Exit;
    end;
  end;
end;

function LoadRecentNames(Ini: TCustomIniFile): TRecentNames;
var Count, I: integer;
begin
  Result := nil;
  Count := Ini.ReadInteger('RecentNames', 'Count', 0);
  if Count < 0 then Count := 0;
  if Count > MaxRecentNames then Count := MaxRecentNames;
  for I := Count - 1 downto 0 do
    RememberRecentName(Result, Ini.ReadString('RecentNames', 'Name' + IntToStr(I + 1), ''));
end;

procedure SaveRecentNames(Ini: TCustomIniFile; const Names: TRecentNames);
var I: integer;
begin
  Ini.EraseSection('RecentNames');
  Ini.WriteInteger('RecentNames', 'Count', Length(Names));
  for I := 0 to High(Names) do
    Ini.WriteString('RecentNames', 'Name' + IntToStr(I + 1), Names[I]);
end;

end.
