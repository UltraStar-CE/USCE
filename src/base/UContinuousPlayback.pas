unit UContinuousPlayback;

{$mode delphi}

interface

type
  TPlaybackProfile = record
    RepeatSelection, ResultTime, HighScoreTime, SongDisplay, SingingDisplay, PlayerTime: integer;
  end;
  TPlaybackProfiles = array[0..1] of TPlaybackProfile;
  TPlaybackSongs = array of integer;
  TPlaybackStage = (psStopped, psSong, psResults, psHighScores, psAdvance, psPlayers);
  TContinuousDisplay = record
    Lyrics, Progress, Notes, PlayerInfo, Feedback: boolean;
  end;

  // Session policy has no dependency on menus, media, microphones or players.
  TContinuousPlayback = class
  private
    Songs: TPlaybackSongs;
    Rejected: array of boolean;
    Position: integer;
    Ordered, RepeatSongs: boolean;
    LastTick, Remaining: cardinal;
    ClockStarted: boolean;
    procedure Shuffle;
  public
    Stage: TPlaybackStage;
    Scored, Paused: boolean;
    ResultSeconds, HighScoreSeconds, PlayerSeconds, Skipped: integer;
    procedure PreparePlayers;
    procedure Start(const Selection: TPlaybackSongs; FirstSong: integer;
      InOrder, RepeatSelection, WithPlayers: boolean);
    procedure ReplaceUpcoming(const Selection: TPlaybackSongs);
    function NextSong(out Song: integer): boolean;
    function PreviousSong(out Song: integer): boolean;
    procedure RejectCurrentSong;
    procedure FinishSong(ShowResults: boolean);
    procedure NextStage;
    function Tick(Now: cardinal; Suspended: boolean): boolean;
    procedure Stop;
    function Active: boolean;
  end;

function ContinuousDisplay(WithPlayers: boolean; SongMode, SingingMode: integer): TContinuousDisplay;

implementation

function ContinuousDisplay(WithPlayers: boolean; SongMode, SingingMode: integer): TContinuousDisplay;
begin
  // Defaults and invalid values retain the normal display.
  if (SongMode < 0) or (SongMode > 3) then SongMode := 0;
  if (SingingMode < 0) or (SingingMode > 4) then SingingMode := 0;
  Result.Lyrics := SongMode in [0, 1];
  Result.Progress := SongMode in [0, 2];
  Result.Notes := WithPlayers and (SingingMode in [0, 1, 2]);
  Result.PlayerInfo := WithPlayers and (SingingMode in [0, 1, 3]);
  Result.Feedback := WithPlayers and (SingingMode = 0);
end;

procedure TContinuousPlayback.Shuffle;
var I, J, Temp: integer; Bad: boolean;
begin
  for I := High(Songs) downto 1 do
  begin
    J := Random(I + 1);
    Temp := Songs[I]; Songs[I] := Songs[J]; Songs[J] := Temp;
    Bad := Rejected[I]; Rejected[I] := Rejected[J]; Rejected[J] := Bad;
  end;
end;

procedure TContinuousPlayback.Start(const Selection: TPlaybackSongs;
  FirstSong: integer; InOrder, RepeatSelection, WithPlayers: boolean);
var I, Temp: integer;
begin
  Stop;
  Songs := Copy(Selection);
  Ordered := InOrder;
  RepeatSongs := RepeatSelection;
  Scored := WithPlayers;
  SetLength(Rejected, Length(Songs));
  if not Ordered then Shuffle;
  Position := -1;
  for I := 0 to High(Songs) do
    if Songs[I] = FirstSong then
    begin
      if Ordered then Position := I - 1
      else begin Temp := Songs[0]; Songs[0] := Songs[I]; Songs[I] := Temp; end;
      Break;
    end;
  if Length(Songs) > 0 then Stage := psAdvance;
end;

procedure TContinuousPlayback.ReplaceUpcoming(const Selection: TPlaybackSongs);
var Current, I, J: integer; Duplicate: boolean;
begin
  if not Active or (Position < 0) or (Position > High(Songs)) then Exit;
  Current := Songs[Position];
  SetLength(Songs, 1);
  Songs[0] := Current;
  for I := 0 to High(Selection) do
  begin
    Duplicate := false;
    for J := 0 to High(Songs) do Duplicate := Duplicate or (Songs[J] = Selection[I]);
    if not Duplicate then
    begin
      SetLength(Songs, Length(Songs) + 1);
      Songs[High(Songs)] := Selection[I];
    end;
  end;
  Position := 0;
  SetLength(Rejected, 0);
  SetLength(Rejected, Length(Songs));
end;

function TContinuousPlayback.NextSong(out Song: integer): boolean;
var Attempts: integer;
begin
  Result := false;
  // Allow the unfinished pass plus one complete reshuffled pass.
  for Attempts := 1 to 2 * Length(Songs) do
  begin
    Inc(Position);
    if Position >= Length(Songs) then
    begin
      if not RepeatSongs then Exit;
      Position := 0;
      if not Ordered then Shuffle;
    end;
    if not Rejected[Position] then
    begin
      Song := Songs[Position];
      Stage := psSong;
      Paused := false;
      Result := true;
      Exit;
    end;
  end;
end;

function TContinuousPlayback.PreviousSong(out Song: integer): boolean;
var Candidate, Attempts: integer;
begin
  Result := false;
  Candidate := Position;
  for Attempts := 1 to Length(Songs) do
  begin
    Dec(Candidate);
    if Candidate < 0 then
    begin
      if not RepeatSongs then Break;
      Candidate := High(Songs);
    end;
    if not Rejected[Candidate] then
    begin
      Position := Candidate;
      Song := Songs[Position];
      Stage := psSong;
      Paused := false;
      Exit(true);
    end;
  end;
  // At the beginning of a non-repeating selection, restart the current song.
  if (Position >= 0) and (Position < Length(Songs)) and not Rejected[Position] then
  begin
    Song := Songs[Position];
    Stage := psSong;
    Paused := false;
    Result := true;
  end;
end;

procedure TContinuousPlayback.RejectCurrentSong;
begin
  if (Position >= 0) and (Position < Length(Rejected)) and not Rejected[Position] then
  begin
    Rejected[Position] := true;
    Inc(Skipped);
  end;
  Stage := psAdvance;
end;

procedure TContinuousPlayback.FinishSong(ShowResults: boolean);
begin
  Paused := false;
  ClockStarted := false;
  if Scored and ShowResults and (ResultSeconds <> 0) then Stage := psResults
  else if Scored and ShowResults and (HighScoreSeconds <> 0) then Stage := psHighScores
  else Stage := psAdvance;
end;

procedure TContinuousPlayback.PreparePlayers;
begin
  if PlayerSeconds = 0 then Exit;
  Stage := psPlayers;
  Paused := false;
  ClockStarted := false;
end;

procedure TContinuousPlayback.NextStage;
begin
  Paused := false;
  ClockStarted := false;
  if Stage = psPlayers then Stage := psSong
  else if (Stage = psResults) and (HighScoreSeconds <> 0) then Stage := psHighScores
  else Stage := psAdvance;
end;

function TContinuousPlayback.Tick(Now: cardinal; Suspended: boolean): boolean;
var Elapsed: cardinal;
begin
  Result := false;
  if not (Stage in [psResults, psHighScores, psPlayers]) then Exit;
  // Negative duration means manual advancement, never an unsigned timeout.
  if ((Stage = psResults) and (ResultSeconds < 0)) or
     ((Stage = psHighScores) and (HighScoreSeconds < 0)) or
     ((Stage = psPlayers) and (PlayerSeconds < 0)) then Exit;
  if not ClockStarted then
  begin
    if Stage = psPlayers then Remaining := cardinal(PlayerSeconds) * 1000
    else if Stage = psResults then Remaining := cardinal(ResultSeconds) * 1000
    else Remaining := cardinal(HighScoreSeconds) * 1000;
    LastTick := Now;
    ClockStarted := true;
  end;
  if Now >= LastTick then Elapsed := Now - LastTick
  else Elapsed := cardinal(QWord(High(cardinal)) - LastTick + Now + 1);
  LastTick := Now;
  if Paused or Suspended then Exit;
  if Elapsed < Remaining then Dec(Remaining, Elapsed)
  else begin NextStage; Result := true; end;
end;

procedure TContinuousPlayback.Stop;
begin
  Stage := psStopped;
  Paused := false;
  Skipped := 0;
  Songs := nil;
  Rejected := nil;
  ClockStarted := false;
end;

function TContinuousPlayback.Active: boolean;
begin
  Result := Stage <> psStopped;
end;

end.
