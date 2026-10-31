unit UFolderFilter;
{$mode Delphi}{$H+}
interface
uses Classes;

// Paths are relative to a configured SongDir. A leading slash anchors a query.
function NormalizeFolderPath(const Value: UTF8String): UTF8String;
function FolderQueryValue(const Value: UTF8String): UTF8String;
function MatchesFolderPath(const Folder, Query: UTF8String): boolean;
procedure AddFolderChoices(const Folder: UTF8String; Depth: integer; Choices: TStrings);

implementation
uses SysUtils;

function NormalizeFolderPath(const Value: UTF8String): UTF8String;
var I, Start: integer; Part, Text: UTF8String;
begin
  Text := StringReplace(Trim(Value), '\', '/', [rfReplaceAll]);
  Result := '/'; Start := 1;
  for I := 1 to Length(Text) + 1 do
    if (I > Length(Text)) or (Text[I] = '/') then
    begin
      Part := Copy(Text, Start, I - Start); Start := I + 1;
      if (Part = '') or (Part = '.') then Continue;
      Result := Result + Part + '/';
    end;
end;

function Fold(const Value: UTF8String): UTF8String;
begin Result := UTF8Encode(UnicodeLowerCase(UTF8Decode(Value))); end;

function FolderQueryValue(const Value: UTF8String): UTF8String;
begin
  Result := Value;
  if (Pos(',', Value) > 0) or (Pos(';', Value) > 0) or (Pos('"', Value) > 0) then
    Result := '"' + StringReplace(Value, '"', '""', [rfReplaceAll]) + '"';
end;

function MatchesFolderPath(const Folder, Query: UTF8String): boolean;
var I, Start: integer; Term, Needle, Haystack: UTF8String; Anchored, Quoted: boolean;
begin
  if Trim(Query) = '' then Exit(true);
  Result := false; Start := 1; Quoted := false;
  Haystack := Fold(NormalizeFolderPath(Folder));
  for I := 1 to Length(Query) + 1 do
  begin
    if (I <= Length(Query)) and (Query[I] = '"') then Quoted := not Quoted;
    if (I > Length(Query)) or (not Quoted and (Query[I] in [',', ';'])) then
    begin
      Term := Trim(Copy(Query, Start, I - Start)); Start := I + 1;
      if Term = '' then Continue;
      if (Length(Term) >= 2) and (Term[1] = '"') and (Term[Length(Term)] = '"') then
        Term := StringReplace(Copy(Term, 2, Length(Term) - 2), '""', '"', [rfReplaceAll]);
      if Term = '' then Continue;
      Anchored := Term[1] in ['/', '\'];
      Needle := Fold(NormalizeFolderPath(Term));
      if Anchored then Result := Pos(Needle, Haystack) = 1
      else Result := Pos(Needle, Haystack) > 0;
      if Result then Exit;
    end;
  end;
end;

procedure AddFolderChoices(const Folder: UTF8String; Depth: integer; Choices: TStrings);
var I, Count: integer; N, Value: UTF8String;
begin
  if Depth = 0 then Exit;
  N := NormalizeFolderPath(Folder); Count := 0;
  if N = '/' then
  begin if Choices.IndexOf(N) < 0 then Choices.Add(N); Exit; end;
  for I := 2 to Length(N) do
    if N[I] = '/' then
    begin
      Inc(Count); Value := Copy(N, 1, I);
      if Choices.IndexOf(Value) < 0 then Choices.Add(Value);
      if (Depth = 1) and (Count = 1) then Exit;
    end;
end;
end.
