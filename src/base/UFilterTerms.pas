unit UFilterTerms;

{$mode delphi}

interface

// Inputs have already been case-folded and transliterated by the song library.
function MatchesFilterTerms(const Value, Query: UTF8String; ExactYears: boolean): boolean;

// Last editable choice; spaces separate years, but remain part of names.
function FilterTermStart(const Query: UTF8String; SpaceSeparates: boolean; QuotedTerms: boolean = false): integer;
function CompleteFilterTerm(const Query, Value: UTF8String; SpaceSeparates: boolean; QuotedTerms: boolean = false): UTF8String;

implementation

uses SysUtils;

function FilterTermStart(const Query: UTF8String; SpaceSeparates: boolean; QuotedTerms: boolean = false): integer;
var I: integer; Quoted: boolean;
begin
  Result := 1; Quoted := false;
  for I := 1 to Length(Query) do
  begin
    if QuotedTerms and (Query[I] = '"') then Quoted := not Quoted;
    if not Quoted and ((Query[I] in [',', ';']) or (SpaceSeparates and (Query[I] = ' '))) then Result := I + 1;
  end;
  while (Result <= Length(Query)) and (Query[Result] = ' ') do Inc(Result);
end;

function CompleteFilterTerm(const Query, Value: UTF8String; SpaceSeparates: boolean; QuotedTerms: boolean = false): UTF8String;
begin
  Result := Copy(Query, 1, FilterTermStart(Query, SpaceSeparates, QuotedTerms) - 1) + Value + ', ';
end;

function MatchesWords(const Value, Query: UTF8String): boolean;
var I, First: integer; Word: UTF8String;
begin
  Result := true;
  First := 1;
  for I := 1 to Length(Query) + 1 do
    if (I > Length(Query)) or (Query[I] = ' ') then
    begin
      Word := Copy(Query, First, I - First);
      if (Word <> '') and (Pos(Word, Value) = 0) then Exit(false);
      First := I + 1;
    end;
end;

function MatchesFilterTerms(const Value, Query: UTF8String; ExactYears: boolean): boolean;
var I, First, Year: integer; Term: UTF8String; HaveTerm, Match: boolean;
begin
  if Trim(Query) = '' then Exit(true);
  Result := false;
  HaveTerm := false;
  First := 1;
  for I := 1 to Length(Query) + 1 do
    if (I > Length(Query)) or (Query[I] in [',', ';']) or
       (ExactYears and (Query[I] = ' ')) then
    begin
      Term := Trim(Copy(Query, First, I - First));
      First := I + 1;
      if Term = '' then Continue;
      HaveTerm := true;
      if ExactYears then
        Match := TryStrToInt(Term, Year) and (Year > 0) and (IntToStr(Year) = Value)
      else
        Match := MatchesWords(Value, Term);
      Result := Result or Match;
    end;
  if not HaveTerm then Result := false;
end;

end.
