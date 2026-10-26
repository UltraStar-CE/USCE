program song_snapshot_test;
{$mode Delphi}{$H+}{$ASSERTIONS ON}
uses SysUtils, fpjson, URemoteSongSnapshot;
var Snapshot: TRemoteSongSnapshot; Songs, Page: TJSONArray; OriginalId: string; I: integer; Request, Reply: TJSONObject;
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
    Request := TJSONObject.Create(['snapshotId', OriginalId, 'offset', 0, 'limit', 100]);
    try
      Reply := Snapshot.Query(Request);
      try Assert(Reply.Get('error', '') = 'snapshot_changed'); finally Reply.Free; end;
      Request.Strings['snapshotId'] := Snapshot.Id;
      Reply := Snapshot.Query(Request);
      try
        Assert(Reply.Find('error') = nil);
        Assert(Reply.Arrays['songs'].Count = 100);
      finally Reply.Free; end;
      Request.Integers['limit'] := 101;
      Reply := Snapshot.Query(Request);
      try Assert(Reply.Get('error', '') = 'invalid_page'); finally Reply.Free; end;
      Request.Delete('offset');
      Request.Add('offset', 0.5);
      Reply := Snapshot.Query(Request);
      try Assert(Reply.Get('error', '') = 'invalid_page'); finally Reply.Free; end;
    finally Request.Free; end;
    Page := Snapshot.Chunk(-1, 100);
    try Assert(Page.Count = 0); finally Page.Free; end;
  finally Songs.Free; Snapshot.Free; end;
  WriteLn('Generic song snapshot: paging, stable identity, privacy and ownership passed');
end.
