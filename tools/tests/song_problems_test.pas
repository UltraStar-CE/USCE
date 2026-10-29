program SongProblemsTest;
{$mode Delphi}{$codepage utf8}
uses SysUtils, Classes, UPath, USongProblems;
var Store: TSongProblems; FileName, A, B: IPath; Failed: boolean;
procedure Check(Value: boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
begin
 SetMultiByteConversionCodePage(CP_UTF8);
 FileName := Path(UTF8String(ParamStr(1))).Append('problems.json');
 A := Path('/songs/Grüße/song.txt'); B := Path('/songs/Other/song.txt');
 Store := TSongProblems.Create(FileName);
 Check(not Store.IsFlagged(A), 'initially unflagged');
 Store.Toggle(A); Store.Toggle(B); Store.Free;
 Store := TSongProblems.Create(FileName);
 Check(Store.IsFlagged(A) and Store.IsFlagged(B), 'persist Unicode paths and separate songs');
 Store.Toggle(A); Store.Free;
 Store := TSongProblems.Create(FileName);
 Check(not Store.IsFlagged(A) and Store.IsFlagged(B), 'unflag one song without losing another');
 Store.Free;
 Store := TSongProblems.Create(Path(UTF8String(ParamStr(1))).Append('missing/sub/problems.json'));
 Failed := false;
 try Store.Toggle(A); except Failed := true; end;
 Check(Failed and not Store.IsFlagged(A), 'failed persistence does not change memory state');
 Store.Free;
 WriteLn('PASS: Unicode paths, persistence, independent songs, unflagging and failed-write rollback');
end.
