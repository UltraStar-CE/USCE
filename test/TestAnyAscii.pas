program TestAnyAscii;

{$MODE Delphi}
{$CODEPAGE UTF8}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  SysUtils, anyascii;

procedure Check(const Input, Expected: UTF8String);
var
  Actual: UTF8String;
begin
  Actual := UTF8Encode(UCS4StringToWideString(
    transliterate(WideStringToUCS4String(UTF8Decode(Input)))));
  if Actual <> Expected then
    raise Exception.CreateFmt('Expected "%s", got "%s"', [Expected, Actual]);
end;

var
  CodePoint: Cardinal;
  Mapping: PAnsiChar;
  Count: Integer;
  LongText: UTF8String;
  Checksum: QWord;
begin
  Check('王', 'Wang');
  Check('小', 'Xiao');
  Check('王小 Björk', 'WangXiao Bjork');
  LongText := StringOfChar('A', 40000);
  Check(LongText, LongText);

  // Exercise every table entry, including bank offsets above signed 16-bit range.
  Checksum := 0;
  for CodePoint := 0 to $10FFFF do
  begin
    Count := anyascii.anyascii(CodePoint, Mapping);
    if (Count < 0) or (Count > 127) then
      raise Exception.CreateFmt('Invalid mapping length at U+%.4X', [CodePoint]);
    if Count > 0 then
      Inc(Checksum, Byte(Mapping[Count - 1]));
  end;
  WriteLn('AnyASCII Unicode, long-string and full-table checks passed: ', Checksum);
end.
