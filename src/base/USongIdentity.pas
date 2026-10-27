unit USongIdentity;
{$mode delphi}{$codepage utf8}
interface
uses Classes, USong;
function FindDuplicateIdentity(LibrarySongs: TList; out First, Second: TSong): boolean;
procedure RenameSongIdentity(LibrarySongs: TList; Song: TSong;
  const Artist, Title: UTF8String);
implementation
uses SysUtils, UPath, UTextEncoding, UUnicodeUtils;
function IdentityKey(const Artist, Title: UTF8String): string;
begin
  Result := IntToStr(Length(Artist)) + ':' + Artist + Title;
end;
function FindDuplicateIdentity(LibrarySongs: TList; out First, Second: TSong): boolean;
var Keys: TStringList; I, J: integer; Song: TSong; A, B: IPath;
begin
  Result := false; First := nil; Second := nil;
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := true;
    for I := 0 to LibrarySongs.Count - 1 do
    begin
      Song := TSong(LibrarySongs[I]);
      if (Song <> nil) and not Song.Main then
        Keys.AddObject(IdentityKey(Song.Artist, Song.Title), Song);
    end;
    Keys.Sort;
    I := 0;
    while I < Keys.Count - 1 do
    begin
      J := I + 1;
      while (J < Keys.Count) and (Keys[J] = Keys[I]) do
      begin
        First := TSong(Keys.Objects[I]); Second := TSong(Keys.Objects[J]);
        A := First.Path.Append(First.FileName).GetAbsolutePath;
        B := Second.Path.Append(Second.FileName).GetAbsolutePath;
        if not A.Equals(B, {$IFDEF MSWINDOWS}true{$ELSE}false{$ENDIF}) then Exit(true);
        Inc(J);
      end;
      I := J;
    end;
    First := nil; Second := nil;
  finally Keys.Free; end;
end;
function ReadBytes(const Filename: IPath): RawByteString;
var Stream: TBinaryFileStream;
begin
  Stream := TBinaryFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Stream.Size);
    if Result <> '' then Stream.ReadBuffer(Result[1], Length(Result));
  finally Stream.Free; end;
end;
procedure RenameSongIdentity(LibrarySongs: TList; Song: TSong;
  const Artist, Title: UTF8String);
var I, Start, Stop, AfterLine, Colon, Offset, BackupIndex: integer;
  Other: TSong; Source, Updated, Line, EncArtist, EncTitle, Tag: RawByteString;
  Filename, Temp, Backup: IPath; Stream: TBinaryFileStream;
  FoundArtist, FoundTitle: boolean; ID: TGUID; Encoding: TEncoding;
  NewArtist, NewTitle: UTF8String;
begin
  NewArtist := Trim(Artist); NewTitle := Trim(Title);
  if (NewArtist = '') or (NewTitle = '') or
     (Pos(#10, Artist + Title) > 0) or (Pos(#13, Artist + Title) > 0) or
     (Pos(#0, Artist + Title) > 0) then raise Exception.Create('DUPLICATE_NAME_EMPTY');
  for I := 0 to LibrarySongs.Count - 1 do
  begin
    Other := TSong(LibrarySongs[I]);
    if (Other <> Song) and (Other.Artist = NewArtist) and (Other.Title = NewTitle) then
      raise Exception.Create('DUPLICATE_NAME_EXISTS');
  end;
  Filename := Song.Path.Append(Song.FileName);
  Source := ReadBytes(Filename);
  Encoding := Song.Encoding;
  if Encoding = encAuto then
    if IsUTF8String(Source) then Encoding := encUTF8 else Encoding := encCP1252;
  if not EncodeStringUTF8(NewArtist, EncArtist, Encoding) or
     not EncodeStringUTF8(NewTitle, EncTitle, Encoding) then
    raise Exception.Create('DUPLICATE_NAME_ENCODING');
  Updated := ''; Start := 1; FoundArtist := false; FoundTitle := false;
  while Start <= Length(Source) do
  begin
    Stop := Start;
    while (Stop <= Length(Source)) and not (Source[Stop] in [#10, #13]) do Inc(Stop);
    AfterLine := Stop;
    if (AfterLine <= Length(Source)) and (Source[AfterLine] = #13) then Inc(AfterLine);
    if (AfterLine <= Length(Source)) and (Source[AfterLine] = #10) then Inc(AfterLine);
    Line := Copy(Source, Start, Stop - Start);
    Offset := 1;
    if (Start = 1) and (Copy(Line, 1, 3) = RawByteString(UTF8_BOM)) then Offset := 4;
    if (Offset <= Length(Line)) and (Line[Offset] <> '#') and (Trim(Line) <> '') then
    begin
      Updated := Updated + Copy(Source, Start, MaxInt);
      Break;
    end;
    Colon := Pos(':', Line);
    if (Colon > Offset) and (Line[Offset] = '#') then
    begin
      Tag := UpperCase(Trim(Copy(Line, Offset + 1, Colon - Offset - 1)));
      if Tag = 'ARTIST' then begin Line := Copy(Line, 1, Colon) + EncArtist; FoundArtist := true; end;
      if Tag = 'TITLE' then begin Line := Copy(Line, 1, Colon) + EncTitle; FoundTitle := true; end;
    end;
    Updated := Updated + Line + Copy(Source, Stop, AfterLine - Stop);
    Start := AfterLine;
  end;
  if not FoundArtist or not FoundTitle then raise Exception.Create('DUPLICATE_NAME_HEADERS');
  CreateGUID(ID);
  Temp := UPath.Path(Filename.ToUTF8 + '.' + GUIDToString(ID) + '.tmp');
  BackupIndex := 0;
  repeat
    Inc(BackupIndex);
    Backup := UPath.Path(Filename.ToUTF8 + '.usce-backup-' + IntToStr(BackupIndex));
  until not Backup.Exists;
  try
    Stream := TBinaryFileStream.Create(Temp, fmCreate);
    try Stream.WriteBuffer(Updated[1], Length(Updated)); finally Stream.Free; end;
    if ReadBytes(Filename) <> Source then raise Exception.Create('DUPLICATE_NAME_CHANGED');
    if not Filename.Rename(Backup) then raise Exception.Create('DUPLICATE_NAME_WRITE');
    if not Temp.Rename(Filename) then
    begin
      Backup.Rename(Filename);
      raise Exception.Create('DUPLICATE_NAME_WRITE');
    end;
  finally if Temp.Exists then Temp.DeleteFile; end;
  Song.Artist := NewArtist; Song.Title := NewTitle;
  Song.ArtistASCII := LowerCase(TransliterateToASCII(NewArtist));
  Song.TitleASCII := LowerCase(TransliterateToASCII(NewTitle));
  Song.MD5 := '';
end;
end.
