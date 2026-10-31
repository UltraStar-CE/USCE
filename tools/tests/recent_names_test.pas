program RecentNamesTest;
{$mode delphi}
{$codepage utf8}
uses SysUtils, IniFiles, URecentNames;
var Entry: TNameEntryState; Suggestions: TRecentNames;
    Names, Loaded, Teams: TRecentNames; Ini: TMemIniFile; I: integer; Editing: boolean; Typed: UTF8String;

procedure Expect(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

begin
  RememberRecentName(Suggestions, 'Daniel');
  Entry.Assign('Player1');
  Entry.Suggest(Suggestions);
  Expect(Entry.Prediction = '', 'Untyped model offered a prediction');
  Entry.TypeText('D'); Entry.Suggest(Suggestions);
  Expect((Entry.Value = 'D') and (Entry.Suffix = 'aniel'), 'Model did not replace the initial name or expose its suffix');
  Entry.TypeText('a'); Entry.Suggest(Suggestions);
  Expect((Entry.Value = 'Da') and (Entry.Suffix = 'niel'), 'Model typing did not append');
  Expect(Entry.Cancel and (Entry.Value = 'Da'), 'Cancel changed typed input');
  Entry.TypeText('n'); Entry.Suggest(Suggestions);
  Expect(Entry.Accept and (Entry.Value = 'Daniel'), 'Model did not confirm the suggestion');
  Entry.TypeText('!');
  Expect(Entry.Value = 'Daniel!', 'Typing after confirmation replaced the name');
  Entry.Finish;
  Entry.TypeText('D'); Entry.Suggest(Suggestions);
  Expect(Entry.Finish and (Entry.Value = 'Daniel') and not Entry.Editing, 'Focus loss did not accept the prediction and finish editing');
  Entry.TypeText('A');
  Expect(Entry.Value = 'A', 'A new edit did not replace the confirmed name');
  Entry.Assign('Änne😀'); Entry.Backspace;
  Expect(Entry.Value = 'Änne', 'Backspace split a supplementary UTF-8 character');
  Entry.TypeText('!');
  Expect(Entry.Value = 'Änne!', 'Typing after deletion replaced the remaining name');
  Entry.Assign(''); Entry.Backspace;
  Expect((Entry.Value = '') and Entry.Editing, 'Deleting an empty name failed');
  RememberRecentName(Suggestions, 'Änne');
  Entry.Assign('Player1'); Entry.TypeText('än'); Entry.Suggest(Suggestions);
  Expect((Entry.Prediction = 'Änne') and (Entry.Suffix = 'ne'), 'Unicode model prediction or suffix failed');
  Entry.Suggest(Suggestions, false);
  Expect(Entry.Prediction = '', 'Disabled prediction remained active');
  Entry.Assign('Daniel'); Entry.Suggest(Suggestions);
  Expect(not Entry.Accept and not Entry.Cancel, 'An absent prediction reported a change');
  Entry.TypeText('Q'); Entry.Suggest(Suggestions);
  Expect(not Entry.Finish and (Entry.Value = 'Q') and not Entry.Editing,
    'Finishing unmatched input changed its value or left editing active');
  Entry.TypeText('D'); Entry.Suggest(Suggestions); Entry.Assign('Saved name');
  Expect((Entry.Value = 'Saved name') and (Entry.Prediction = '') and not Entry.Editing,
    'Assign retained an earlier prediction or editing session');
  Editing := false;
  Typed := TypeNameInput(Editing, 'Player1', 'D');
  Expect((Typed = 'D') and Editing, 'First character did not replace existing name');
  Typed := TypeNameInput(Editing, Typed, 'a');
  Expect(Typed = 'Da', 'Subsequent typing did not append');
  Editing := true;
  Expect(TypeNameInput(Editing, 'D', 'n') = 'Dn', 'Typing after an edit replaced it');
  Editing := false;
  Expect(TypeNameInput(Editing, 'Other field', 'Ä') = 'Ä', 'Fresh focus did not replace text');
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
  RememberRecentName(Names, 'Änne');
  Expect(PredictRecentName(Names, 'än') = 'Änne', 'Unicode prefix comparison failed');
  RememberRecentName(Names, '');
  RememberRecentName(Names, 'broken' + #10 + 'name');
  Expect(Names[0] = 'Änne', 'Empty or multiline value changed history');
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
  WriteLn('PASS: name editing, prediction confirmation/cancellation, Unicode, MRU and persistence');
end.
