program RecentNamesTest;
{$mode delphi}
{$codepage utf8}
uses SysUtils, IniFiles, URecentNames;
var Names, Loaded, Teams: TRecentNames; Ini: TMemIniFile; I: integer; Editing: boolean; Typed: UTF8String;

procedure Expect(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

begin
  Editing := false;
  Typed := TypeNameInput(Editing, 'Player1', 'D');
  Expect((Typed = 'D') and Editing, 'First character did not replace existing name');
  Typed := TypeNameInput(Editing, Typed, 'a');
  Expect(Typed = 'Da', 'Subsequent typing did not append');
  Editing := true;
  Expect(TypeNameInput(Editing, 'D', 'n') = 'Dn', 'Typing after an edit replaced it');
  Editing := false;
  Expect(TypeNameInput(Editing, 'Other field', 'Ã„') = 'Ã„', 'Fresh focus did not replace text');
  RememberRecentName(Names, 'Daniel');
  RememberRecentName(Names, 'Dani');
  Expect(PredictRecentName(Names, 'Da') = 'Dani', 'MRU order ignored');
  RememberRecentName(Names, 'Daniel');
  Expect(PredictRecentName(Names, 'da') = 'Daniel', 'Reusing a name did not promote it');
  Expect(Length(Names) = 2, 'Reusing a name duplicated it');
  RememberRecentName(Names, 'DANIEL');
  Expect((Length(Names) = 2) and (Names[0] = 'DANIEL'), 'Case-insensitive deduplication failed');
  Expect(PredictRecentName(Names, '') = '', 'Untyped field predicted a name');
  Expect(PredictRecentName(Names, 'x') = '', 'Nonmatching prefix predicted a name');
  RememberRecentName(Names, 'Adam');
  RememberRecentName(Names, 'Ada');
  Expect(PredictRecentName(Names, 'Ada') = '', 'Exact match skipped in favor of older longer name');
  RememberRecentName(Names, 'Ã„nne');
  Expect(PredictRecentName(Names, 'Ã¤n') = 'Ã„nne', 'Unicode prefix comparison failed');
  RememberRecentName(Names, '');
  RememberRecentName(Names, 'broken' + #10 + 'name');
  Expect(Names[0] = 'Ã„nne', 'Empty or multiline value changed history');
  Ini := TMemIniFile.Create('');
  try
    SaveRecentNames(Ini, Names);
    Teams := LoadRecentNames(Ini, 'RecentTeamNames');
    Expect(Length(Teams) = 0, 'Team history should start empty');
    RememberRecentName(Teams, 'Daniel Team');
    SaveRecentNames(Ini, Teams, 'RecentTeamNames');
    Teams := LoadRecentNames(Ini, 'RecentTeamNames');
    Expect(PredictRecentName(Teams, 'Da') = 'Daniel Team', 'Team history did not round-trip');
    Loaded := LoadRecentNames(Ini);
    Expect(PredictRecentName(Loaded, 'da') = 'DANIEL', 'Team save changed player suggestions');
    RememberRecentName(Loaded, 'David');
    SaveRecentNames(Ini, Loaded);
    Teams := LoadRecentNames(Ini, 'RecentTeamNames');
    Expect((Length(Teams) = 1) and (Teams[0] = 'Daniel Team'), 'Player save changed team history');
    SaveRecentNames(Ini, Names);
    Loaded := LoadRecentNames(Ini);
    Expect(Length(Loaded) = Length(Names), 'History count did not round-trip');
    for I := 0 to High(Names) do Expect(Loaded[I] = Names[I], 'History order/text did not round-trip');
    for I := 1 to MaxRecentNames + 5 do RememberRecentName(Names, 'Name' + IntToStr(I));
    Expect(Length(Names) = MaxRecentNames, 'History limit failed');
    Expect(Names[0] = 'Name' + IntToStr(MaxRecentNames + 5), 'Most recent name lost at limit');
    Ini.WriteInteger('RecentNames', 'Count', -1);
    Loaded := LoadRecentNames(Ini);
    Expect(Length(Loaded) = 0, 'Negative count loaded entries');
  finally
    Ini.Free;
  end;
  WriteLn('PASS: MRU promotion, prefix matching, Unicode, deduplication and persistence');
end.
