program FilterTermsTest;
{$mode delphi}
{$R+}{$Q+}
uses SysUtils, UFilterTerms;
procedure Check(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;
begin
  Check(MatchesFilterTerms('1987', '1987 1988,1989;2000', true), 'first year');
  Check(MatchesFilterTerms('1988', '1987 1988,1989;2000', true), 'space year');
  Check(MatchesFilterTerms('1989', '1987 1988,1989;2000', true), 'comma year');
  Check(MatchesFilterTerms('2000', '1987 1988,1989;2000', true), 'semicolon year');
  Check(not MatchesFilterTerms('198', '1987 1988,1989;2000', true), 'partial year');
  Check(not MatchesFilterTerms('1987', '198', true), 'short year');
  Check(not MatchesFilterTerms('0', '0', true), 'unknown year');
  Check(not MatchesFilterTerms('1987', ',; ', true), 'separators only');
  Check(not MatchesFilterTerms('1987', 'nope', true), 'invalid year');
  Check(MatchesFilterTerms('german', 'german, english', false), 'first language');
  Check(MatchesFilterTerms('english', 'german; english', false), 'second language');
  Check(not MatchesFilterTerms('french', 'german, english', false), 'excluded language');
  Check(MatchesFilterTerms('brazilian portuguese', 'german; brazilian portuguese', false), 'multiword language');
  Check(not MatchesFilterTerms('portuguese', 'brazilian portuguese', false), 'multiword conjunction');
  Check(MatchesFilterTerms('rock & roll', 'rock & roll', false), 'punctuation');
  Check(MatchesFilterTerms('german', '', false), 'empty row');
  Writeln('Filter alternative tests passed');
end.
