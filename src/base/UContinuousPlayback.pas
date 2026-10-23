unit UContinuousPlayback;

{$mode delphi}

interface

type
  TPlaybackSongs = array of integer;
  TPlaybackStage = (psStopped, psSong, psResults, psHighScores, psAdvance);

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
    ResultSeconds, HighScoreSeconds, Skipped: integer;
    procedure Start(const Selection: TPlaybackSongs; FirstSong: integer;
      InOrder, RepeatSelection, WithPlayers: boolean);
    function NextSong(out Song: integer): boolean;
    function PreviousSong(out Song: integer): boolean;
    procedure RejectCurrentSong;
    procedure FinishSong(ShowResults: boolean);
    procedure NextStage;
    function Tick(Now: cardinal; Suspended: boolean): boolean;
    procedure Stop;
    function Active: boolean;
  end;

implementation

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
  if Scored and ShowResults and (ResultSeconds > 0) then Stage := psResults
  else if Scored and ShowResults and (HighScoreSeconds > 0) then Stage := psHighScores
  else Stage := psAdvance;
end;

procedure TContinuousPlayback.NextStage;
begin
  Paused := false;
  ClockStarted := false;
  if (Stage = psResults) and (HighScoreSeconds > 0) then Stage := psHighScores
  else Stage := psAdvance;
end;

function TContinuousPlayback.Tick(Now: cardinal; Suspended: boolean): boolean;
var Elapsed: cardinal;
begin
  Result := false;
  if not (Stage in [psResults, psHighScores]) then Exit;
  if not ClockStarted then
  begin
    if Stage = psResults then Remaining := cardinal(ResultSeconds) * 1000
    else Remaining := cardinal(HighScoreSeconds) * 1000;
    LastTick := Now;
    ClockStarted := true;
  end;
  Elapsed := Now - LastTick;
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
