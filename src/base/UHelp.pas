unit UHelp;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

interface
uses
  ULog,
  UPathUtils,
  UFilesystem,
  IniFiles,
  SysUtils;

type
  TKeymap = record
    Key:    array of string; //key-combination translated
    Text:   string;   //description text
  end;

  TSection = record
    name:   string;
    Keys:   array of TKeymap;
  end;

  TSub = record
    title:  string;
    text:   array of AnsiString;
  end;

  TKeyNames = record
    Key:    array of string;
  end;

  TTextResultSection = record
    name:           string;
    Keys:           array of TKeyNames;
    KeyDescription: array of AnsiString;
  end;

  TTextResult = record
    Title:          String;
    Description:    AnsiString;
    Subs:           array of TSub;
    Sections:       array of TTextResultSection;
  end;

  TKeys = record
    Key:  string;
    Translation: string;
  end;

  TEntry = record
    ID:           string;
    Title:        string;
    Description:  string;
    Subs:         array of TSub;
    Sections:     array of TSection;
  end;

  TLanguageList = record
    Name:   string;
  end;

  THelp = class
    private
      actualID:     string;
      ScrollPos:    double;
      Entry:        array of TEntry;
      SEntry:       array of TEntry;
      AEntry:       TEntry;
      List:         array of TLanguageList;
      Implode_Glue1, Implode_Glue2: String;
      procedure LoadLanguage(const Language: String);
    public
      MaxLines: integer;
      constructor Create;
      procedure LoadList;

      procedure ChangeLanguage(Language: String);
      //procedure LoadKeys;
      function SetHelpID(ID: String):boolean;
      function GetHelpID(): string;
      function GetHelpStr(): TTextResult;
      procedure SetScrollPos(pos: double);
      function GetScrollPos(): double;
  end;


var
  Help:   THelp;


implementation
uses
  UFiles,
  ULanguage,
  Classes,
  sdl2;

//----------
//Create - Construct Class then LoadList + Standard Language + Set Standard Implode Glues
//----------
constructor THelp.Create;
var
  I, J, K: Integer;
begin
  LoadList;
  MaxLines := 0;
  //LoadKeys;
  //Set Implode Glues for Backward Compatibility
  Implode_Glue1 := ', ';
  Implode_Glue2 := ' and ';

  // Missing help files must not prevent the game from starting.

  //Standard Language (If a Language File is Incomplete)
  //Then use English Language
  for I := 0 to high(List) do //Search for English Language
  begin
    //English Language Found -> Load
    if Uppercase(List[I].Name) = 'ENGLISH' then
    begin
      ChangeLanguage('English');

      SetLength(SEntry, Length(Entry));

      for J := low(Entry) to high(Entry) do
      begin
        SetLength(SEntry[J].Sections, Length(Entry[J].Sections));
        SEntry[J].ID := Entry[J].ID;
        SEntry[J].Title := Entry[J].Title;
        SEntry[J].Description := Entry[J].Description;
        SEntry[J].Subs := Entry[J].Subs;
        for K := low(Entry[J].Sections) to high(Entry[J].Sections) do
          SEntry[J].Sections[K] := Entry[J].Sections[K];
      end;

      SetLength(List, 0);

      Break;
    end;

    if (I = high(List)) then
      Log.LogError('English language file missing! No standard Translation loaded (Help System)');
  end;

  actualID := '';
  //Standard Language END

end;

//----------
//LoadList - Parse the Help Dir searching Translations
//----------
procedure THelp.LoadList;
var
  SR:     TSearchRec;   // for parsing directory
begin
  SetLength(List, 0);

  if FindFirst(LanguagesPath.ToNative() + '*.ini', 0, SR) = 0 then
  begin
    repeat
      SetLength(List, Length(List)+1);
      SR.Name := ChangeFileExt(SR.Name, '');
      List[High(List)].Name := SR.Name;
    until FindNext(SR) <> 0;
    SysUtils.FindClose(SR);
  end; // if FindFirst
end;

//----------
//ChangeLanguage - Load the specified LanguageFile
//----------
procedure THelp.ChangeLanguage(Language: String);
begin
  SetLength(Entry, 0);
  Implode_Glue1 := ', ';
  Implode_Glue2 := ' and ';
  try
    LoadLanguage(Language);
  except
    // Help is optional. An unreadable translation uses the English cache.
    SetLength(Entry, 0);
    if not SameText(Language, 'English') then
    begin
      try
        LoadLanguage('English');
      except
        SetLength(Entry, 0);
      end;
    end;
  end;
end;

procedure THelp.LoadLanguage(const Language: String);
var
  IniFile:    TIniFile;
  E:          integer; // entry
  S:          TStringList;
  SL :        TStringList;
  num:        Integer;
  I, J:       Integer;
  Keys:       array of TKeys;
  tempStr:    AnsiString;
  ActSection: integer;
  ActSub:     integer;
  ActKey:     integer;
  ActSubEntry:    integer;
  InvalidEntry: boolean;
  DefaultTitle, DefaultDescription: string;

  function GetIDStr(ID: integer):string;
  var
    S: string;
  begin
    S := IntToStr(ID);
    while (Length(S)<3) do S := '0' + S;
    Result := 'ID_' + S;
  end;

  function GetKeyTranslation(Key: string):string;
  var
    I:  Integer;
  begin
    Result := Key;
    for I := 0 to Length(Keys) - 1 do
    begin
      if Keys[I].Key=Key then
      begin
        Result := Keys[I].Translation;
        break;
      end;
    end;
  end;

begin
  IniFile := nil;
  S := nil;
  try
  IniFile := TIniFile.Create(LanguagesPath.toNative() + Language + '.ini');

  SetLength(Keys, 0);
  //read keys
  S := TStringList.Create;
  IniFile.ReadSectionValues('Keymap', S);

  SetLength(Keys, S.Count);
  for E := 0 to high(Keys) do
  begin
    if S.Names[E] = 'IMPLODE_GLUE1' then
      Implode_Glue1 := S.ValueFromIndex[E]+ ' '
    else if S.Names[E] = 'IMPLODE_GLUE2' then
      Implode_Glue2 := ' ' + S.ValueFromIndex[E] + ' ';

    Keys[E].Key := S.Names[E];
    Keys[E].Translation := S.ValueFromIndex[E];
  end;

  SetLength(Entry, 0);
  num := IniFile.ReadInteger('config', 'NumIDs', 0);

  if (num < 0) or (num > 1000) then
    raise EConvertError.Create('Invalid help entry count');

  if num>0 then
  begin
    SetLength(Entry, num);
    for I:=1 to num do
    begin

      InvalidEntry := false;
      DefaultTitle := '';
      DefaultDescription := '';
      for J := 0 to High(SEntry) do
        if SEntry[J].ID = GetIDStr(I) then
        begin
          DefaultTitle := SEntry[J].Title;
          DefaultDescription := SEntry[J].Description;
          break;
        end;
      Entry[I-1].ID:= GetIDStr(I);
      if not IniFile.SectionExists(GetIDStr(I)) then
      begin
        Entry[I-1].ID := '';
        Continue;
      end;
      Entry[I-1].Title := IniFile.ReadString(GetIDStr(I), 'Title', DefaultTitle);
      Entry[I-1].Description := IniFile.ReadString(GetIDStr(I), 'Description', DefaultDescription);

      //read subs, sections and keymapping
      S.Clear;
      IniFile.ReadSectionValues(GetIDStr(I), S);
      ActSub := -1;
      ActSubEntry := -1;
      ActSection := -1;
      ActKey := -1;

      //SetLength(Entry[I-1].Keys, S.Count-2);
      for E := 0 to S.Count-1 do
      begin
        if S.Names[E] = 'IMPLODE_GLUE1' then
          Implode_Glue1 := S.ValueFromIndex[E]+ ' '
        else if S.Names[E] = 'IMPLODE_GLUE2' then
          Implode_Glue2 := ' ' + S.ValueFromIndex[E] + ' ';

        if not SameText(S.Names[E], 'Title') and not SameText(S.Names[E], 'Description') and
           not SameText(S.Names[E], 'IMPLODE_GLUE1') and not SameText(S.Names[E], 'IMPLODE_GLUE2') then
        begin
          tempStr := S.Names[E];

          SL:=TStringList.Create;
          try
            ExtractStrings(['_'], [], PChar(tempStr), SL);
            if SL.Count = 0 then
            begin
              InvalidEntry := true;
              Continue;
            end;
            //check new Sub
            if SameText(SL[0], 'SUB') then
            begin
              inc(ActSub);
              ActSubEntry := -1;
              SetLength(Entry[I-1].Subs, ActSub+1);
              Entry[I-1].Subs[ActSub].title := S.ValueFromIndex[E];

            end

            //check sub entry
            else if SameText(SL[0], 'ENT') then
            begin
              if ActSub < 0 then
              begin
                InvalidEntry := true;
                Continue;
              end;
              inc(ActSubEntry);
              SetLength(Entry[I-1].Subs[ActSub].text, ActSubEntry+1);
              Entry[I-1].Subs[ActSub].text[ActSubEntry] := S.ValueFromIndex[E];
            end

            //check new section
            else if SameText(SL[0], 'SEC') then
            begin
              inc(ActSection);
              ActKey := -1;
              SetLength(Entry[I-1].Sections, ActSection+1);
              Entry[I-1].Sections[ActSection].name := S.ValueFromIndex[E];
            end

            //read keymap
            else if ActSection=-1 then
            begin
              InvalidEntry := true;
            end else
            begin
              inc(ActKey);
              SetLength(Entry[I-1].Sections[ActSection].Keys, ActKey +1);
              Entry[I-1].Sections[ActSection].Keys[ActKey].Text := S.ValueFromIndex[E];

              SetLength(Entry[I-1].Sections[ActSection].Keys[ActKey].Key, SL.Count);
              for J := 0 to SL.Count-1 do
                Entry[I-1].Sections[ActSection].Keys[ActKey].Key[J] := GetKeyTranslation(SL[J]);
            end;

          Finally
            SL.Free;
          end;

        end;
      end;

      // Malformed localized topics fall back as a whole. In English, retain
      // the usable text and ignore malformed lines rather than losing help.
      if InvalidEntry and not SameText(Language, 'English') then
        Entry[I-1].ID := '';
    end;
  end;

  finally
    S.Free;
    IniFile.Free;
  end;
end;

function THelp.SetHelpID(ID: String):boolean;
var
  E:   integer; // entry
begin
  Result := false;
  ScrollPos := 0.0;

  for E := 0 to high(Entry) do
  begin
    if ID = Entry[E].ID then
    begin
      Result := true;
      AEntry := Entry[E];
      actualID := ID;
      exit;
    end;
  end;

  //Standard Language (If a Language File is Incomplete)
  //Then use Standard Language
  for E := low(SEntry) to high(SEntry) do
  begin
  if ID = SEntry[E].ID then
    begin
      Result := true;
      AEntry := SEntry[E];
      actualID := ID;
      exit;
    end;
  end;
  //Standard Language END
end;

function THelp.GetHelpID(): string;
begin
  Result := actualID;
end;

function THelp.GetHelpStr(): TTextResult;
var
  K, I, J:   Integer;

begin
  Result := Default(TTextResult);
  SetLength(Result.Sections, Length(AEntry.Sections));
  for K := 0 to Length(AEntry.Sections) - 1 do
  begin
    SetLength(Result.Sections[K].Keys, Length(AEntry.Sections[K].Keys));
    SetLength(Result.Sections[K].KeyDescription, Length(AEntry.Sections[K].Keys));
    Result.Sections[K].name := AEntry.Sections[K].name;

    for I := 0 to Length(AEntry.Sections[K].Keys)-1 do
    begin
      SetLength(Result.Sections[K].Keys[I].Key, Length(AEntry.Sections[K].Keys[I].Key));
      for J := 0 to Length(AEntry.Sections[K].Keys[I].Key) - 1 do
      begin
        Result.Sections[K].Keys[I].Key[J] := '[' + AEntry.Sections[K].Keys[I].Key[J] + ']';
      end;
      Result.Sections[K].KeyDescription[I] := AEntry.Sections[K].Keys[I].Text;
    end;
  end;

  SetLength(Result.Subs, Length(AEntry.Subs));
  for K := 0 to Length(AEntry.Subs) - 1 do
  begin
    Result.Subs[K].title := AEntry.Subs[K].title;
    Result.Subs[K].text := AEntry.Subs[K].text;
  end;

  Result.Title := AEntry.Title;
  Result.Description := AEntry.Description;
end;

procedure THelp.SetScrollPos(pos: double);
begin
  ScrollPos := pos;
end;

function THelp.GetScrollPos(): double;
begin
  Result := ScrollPos;
end;

end.
