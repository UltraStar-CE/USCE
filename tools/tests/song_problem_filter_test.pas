program SongProblemFilterTest;
{$mode Delphi}
uses SysUtils, USong, USongs, USongProblems, UPath, UPlatform;
var A,B: TSong; Rows: TSongFilterRows;
procedure Check(Value: boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
begin
 Platform.Init;
 A := TSong.Create; B := TSong.Create;
 A.Path := Path(UTF8String(ParamStr(1))); A.FileName := Path('a.txt'); A.ArtistASCII := 'alpha';
 B.Path := A.Path; B.FileName := Path('b.txt'); B.ArtistASCII := 'beta';
 CatSongs := TCatSongs.Create; SetLength(CatSongs.Song,2); CatSongs.Song[0] := A; CatSongs.Song[1] := B;
 GetSongProblems.Toggle(A.Path.Append(A.FileName));
 Check(CatSongs.SetFilter('yes',fltProblem)=1,'one flagged song');
 Check(A.Visible and not B.Visible,'correct flagged chart');
 Check(CatSongs.SetFilter('no',fltProblem)=1,'one unflagged song');
 Check(B.Visible and not A.Visible,'correct unflagged chart');
 SetLength(Rows,2);Rows[0].Kind:=fltProblem;Rows[0].Query:='yes';
 Rows[1].Kind:=fltArtist;Rows[1].Query:='alpha';
 Check(CatSongs.SetFilters(Rows)=1,'flag filter stacks with artist');
 Rows[1].Query:='beta'; Check(CatSongs.SetFilters(Rows)=0,'stacked criteria remain AND');
 GetSongProblems.Toggle(A.Path.Append(A.FileName));
 Check(CatSongs.SetFilter('yes',fltProblem)=0,'unflagging reflected on next filter');
 CatSongs.Free;CatSongs:=nil; A.Free; B.Free;
 WriteLn('PASS: flagged/unflagged selection, stacked rows and refreshed flags');
end.
