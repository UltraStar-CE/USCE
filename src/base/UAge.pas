unit UAge;

{$mode delphi}

interface

// AGE grammar: comma-separated positive integers (1..999), optionally prefixed
// by a country/authority of at least two letters: 12, DE:16, US:13. Regional
// entries override the unprefixed default; malformed/duplicate entries are unrated.
function AgeForRegion(const Header, Region: string): integer;
function SystemAgeRegion: string;
function LocaleAgeRegion(Locale: string): string;

implementation

uses SysUtils, Classes
  {$IFDEF MSWINDOWS}, Windows{$ENDIF}
  {$IFDEF DARWIN}, MacOSAll{$ENDIF};

function LocaleAgeRegion(Locale: string): string;
var
  I: integer;
begin
  Result := '';
  I := Pos('.', Locale);
  if I > 0 then SetLength(Locale, I - 1);
  I := Pos('@', Locale);
  if I > 0 then SetLength(Locale, I - 1);
  I := Pos('_', Locale);
  if I = 0 then I := Pos('-', Locale);
  if I = 0 then Exit;
  Locale := UpperCase(Copy(Locale, I + 1, MaxInt));
  if (Length(Locale) = 2) and (Locale[1] in ['A'..'Z']) and
    (Locale[2] in ['A'..'Z']) then Result := Locale;
end;

function SystemAgeRegion: string;
var
  Locale: string;
  {$IFDEF MSWINDOWS}Buffer: array[0..15] of char;{$ENDIF}
  {$IFDEF DARWIN}
  CurrentLocale: CFLocaleRef;
  Country: CFStringRef;
  CountryBuffer: array[0..15] of char;
  {$ENDIF}
begin
  Result := '';
  {$IFDEF MSWINDOWS}
  if GetLocaleInfo(LOCALE_USER_DEFAULT, LOCALE_SISO3166CTRYNAME, Buffer, Length(Buffer)) > 0 then
    Exit(UpperCase(string(Buffer)));
  {$ENDIF}
  {$IFDEF DARWIN}
  CurrentLocale := CFLocaleCopyCurrent;
  if CurrentLocale <> nil then
  begin
    Country := CFStringRef(CFLocaleGetValue(CurrentLocale, kCFLocaleCountryCode));
    if (Country <> nil) and CFStringGetCString(Country, @CountryBuffer[0],
      SizeOf(CountryBuffer), kCFStringEncodingUTF8) then
      Result := UpperCase(string(CountryBuffer));
    CFRelease(CurrentLocale);
    if Result <> '' then Exit;
  end;
  {$ENDIF}
  Locale := SysUtils.GetEnvironmentVariable('LC_ALL');
  if Locale = '' then Locale := SysUtils.GetEnvironmentVariable('LC_MESSAGES');
  if Locale = '' then Locale := SysUtils.GetEnvironmentVariable('LANG');
  Result := LocaleAgeRegion(Locale);
end;

function AgeForRegion(const Header, Region: string): integer;
var
  Entries, Seen: TStringList;
  Entry, Key, Number: string;
  I, J, Colon, Value, DefaultAge, RegionalAge: integer;
begin
  Result := -1;
  DefaultAge := -1;
  RegionalAge := -1;
  if Trim(Header) = '' then Exit;
  Entries := TStringList.Create;
  Seen := TStringList.Create;
  try
    Entries.StrictDelimiter := true;
    Entries.Delimiter := ',';
    Entries.QuoteChar := #0;
    Entries.DelimitedText := Header;
    for I := 0 to Entries.Count - 1 do
    begin
      Entry := Trim(Entries[I]);
      Colon := Pos(':', Entry);
      Key := '';
      Number := Entry;
      if Colon > 0 then
      begin
        Key := UpperCase(Trim(Copy(Entry, 1, Colon - 1)));
        if Length(Key) < 2 then Exit;
        for J := 1 to Length(Key) do
          if not (Key[J] in ['A'..'Z']) then Exit;
        Number := Trim(Copy(Entry, Colon + 1, MaxInt));
      end;
      if Seen.IndexOf(Key) >= 0 then Exit;
      Seen.Add(Key);
      if (Length(Number) < 1) or (Length(Number) > 3) then Exit;
      for J := 1 to Length(Number) do
        if not (Number[J] in ['0'..'9']) then Exit;
      if not TryStrToInt(Number, Value) or (Value < 1) then Exit;
      if Key = '' then DefaultAge := Value
      else if Key = UpperCase(Region) then RegionalAge := Value;
    end;
    if RegionalAge >= 0 then Result := RegionalAge
    else Result := DefaultAge;
  finally
    Seen.Free;
    Entries.Free;
  end;
end;

end.
