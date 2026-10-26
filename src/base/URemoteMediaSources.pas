{ Private media lookup from game-owned song metadata. Never serialized to clients. }
unit URemoteMediaSources;
{$mode Delphi}{$H+}
interface
uses SysUtils, fpjson;
type
 TRemoteMediaSources = class
 private
  FEntries: TJSONObject;
 public
  constructor Create;
  destructor Destroy; override;
  procedure Replace(Songs: TJSONArray);
  function Resolve(SongId: integer; const Purpose: string): string;
 end;
implementation
constructor TRemoteMediaSources.Create;
begin inherited; FEntries := TJSONObject.Create; end;
destructor TRemoteMediaSources.Destroy;
begin FEntries.Free; inherited; end;
procedure TRemoteMediaSources.Replace(Songs: TJSONArray);
var Next: TJSONObject; Song, Entry: TJSONObject; I, Id, Existing: integer;
begin
 Next := TJSONObject.Create;
 try
  for I := 0 to Songs.Count - 1 do
  begin
   if Songs.Items[I].JSONType <> jtObject then Continue;
   Song := TJSONObject(Songs.Items[I]);
   Id := Song.Get('songId', -1);
   if Id < 0 then Continue;
   Entry := TJSONObject.Create(['audio', Song.Get('audioPath', ''),
     'cover', Song.Get('coverPath', '')]);
   Existing := Next.IndexOfName(IntToStr(Id));
   if Existing >= 0 then Next.Delete(Existing);
   Next.Add(IntToStr(Id), Entry);
  end;
 except Next.Free; raise; end;
 FEntries.Free; FEntries := Next;
end;
function TRemoteMediaSources.Resolve(SongId: integer; const Purpose: string): string;
var Value: TJSONData; Key: string;
begin
 Result := '';
 if SongId < 0 then Exit;
 if Purpose = 'cover' then Key := 'cover'
 else if (Purpose = 'preview') or (Purpose = 'device-music') then Key := 'audio'
 else Exit;
 Value := FEntries.Find(IntToStr(SongId));
 if (Value <> nil) and (Value.JSONType = jtObject) then
  Result := TJSONObject(Value).Get(Key, '');
end;
end.
