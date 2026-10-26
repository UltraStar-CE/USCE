program song_snapshot_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses SysUtils, fpjson, URemoteSongSnapshot;
var Snapshot: TRemoteSongSnapshot; Songs, Page: TJSONArray; OriginalId: string; I: integer;
begin
  Snapshot := TRemoteSongSnapshot.Create;
  Songs := TJSONArray.Create;
  try
    for I := 0 to 104 do Songs.Add(TJSONObject.Create(['songId', I,
      'title', 'Test', 'audioPath', 'private.wav']));
    Snapshot.Replace(Songs);
    OriginalId := Snapshot.Id;
    Assert(Snapshot.Count = 105);
    Page := Snapshot.Chunk(0, 1000);
    try
      Assert(Page.Count = 100);
      Assert(Pos('private.wav', Page.AsJSON) = 0);
      Assert(TJSONObject(Songs.Items[0]).Get('audioPath', '') = 'private.wav');
    finally Page.Free; end;
    Page := Snapshot.Chunk(100, 100);
    try
      Assert(Page.Count = 5);
      Assert(TJSONObject(Page.Items[0]).Get('songId', -1) = 100);
      TJSONObject(Page.Items[0]).Strings['title'] := 'Changed copy';
    finally Page.Free; end;
    Snapshot.Replace(Songs);
    Assert(Snapshot.Id = OriginalId);
    TJSONObject(Songs.Items[0]).Strings['title'] := 'Changed song';
    Snapshot.Replace(Songs);
    Assert(Snapshot.Id <> OriginalId);
    Page := Snapshot.Chunk(-1, 100);
    try Assert(Page.Count = 0); finally Page.Free; end;
  finally Songs.Free; Snapshot.Free; end;
  WriteLn('Generic song snapshot: paging, stable identity, privacy and ownership passed');
end.
