unit UWebSongCatalogue;

{$mode objfpc}{$H+}

interface

uses Classes, USong, UPath;

type
  TWebSong = record
    Artist, Title, Edition, Genre, Language, Creator: UTF8String;
    Year: integer;
    IsDuet, HasRap: boolean;
    Directory, Cover, Background, Audio, Video, FileName: IPath;
  end;
  TWebSongArray = array of TWebSong;

// Capture on the game thread before starting the server. Worker requests only
// read these values, so menu sorting and editor changes cannot tear a response.
function CaptureWebSongCatalogue(const SongList: TList): TWebSongArray;

implementation

function CaptureWebSongCatalogue(const SongList: TList): TWebSongArray;
var I: integer; Song: TSong;
begin
  Result := nil;
  SetLength(Result, SongList.Count);
  for I := 0 to SongList.Count - 1 do
  begin
    Song := TSong(SongList[I]);
    with Result[I] do
    begin
      Artist := Song.Artist; Title := Song.Title;
      Edition := Song.Edition; Genre := Song.Genre;
      Language := Song.Language; Creator := Song.Creator;
      Year := Song.Year; IsDuet := Song.IsDuet; HasRap := Song.HasRap;
      Directory := Song.Path; Cover := Song.Cover;
      Background := Song.Background; Audio := Song.Audio;
      Video := Song.Video; FileName := Song.FileName;
    end;
  end;
end;

end.
