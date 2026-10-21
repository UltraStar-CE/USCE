program AgeTest;
{$mode delphi}
uses SysUtils, UAge;

procedure Expect(const Header, Region: string; Expected: integer);
begin
  if AgeForRegion(Header, Region) <> Expected then
    raise Exception.Create('Unexpected AGE result: ' + Header + ' / ' + Region);
end;

begin
  Assert(LocaleAgeRegion('C.UTF-8') = '');
  Assert(LocaleAgeRegion('en.UTF-8') = '');
  Assert(LocaleAgeRegion('en_US.UTF-8') = 'US');
  Assert(LocaleAgeRegion('de-AT') = 'AT');
  Assert(LocaleAgeRegion('sr_RS@latin') = 'RS');
  Assert(LocaleAgeRegion('en_8') = '');
  Assert(LocaleAgeRegion('en_USA') = '');
  Expect('12, DE:16, US:13', 'DE', 16);
  Expect('12, DE:16, US:13', 'US', 13);
  Expect('12, DE:16, US:13', 'AT', 12);
  Expect('12, DE:16, US:13', '', 12);
  Expect('DE:16', 'AT', -1);
  Expect('DE:16', '', -1);
  Expect(' de:16 , 12 ', 'DE', 16);
  Expect('PEGI:12, USK:16', 'PEGI', 12);
  Expect('999', '', 999);
  Expect('', 'DE', -1);
  Expect('0', 'DE', -1);
  Expect('-1', 'DE', -1);
  Expect('1000', '', -1);
  Expect('12, DE:bad', '', -1);
  Expect('12, DE:16, de:13', 'DE', -1);
  Expect('12, 14', '', -1);
  Expect('12,', '', -1);
  Expect('12,,US:13', 'US', -1);
  Expect('12, D:13', '', -1);
  Expect('12, DE2:13', '', -1);
  Expect('12, US:+13', '', -1);
  WriteLn('PASS: AGE parsing, regional precedence, default fallback and unknown values');
end.
