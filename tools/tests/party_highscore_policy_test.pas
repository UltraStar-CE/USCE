program PartyHighscorePolicyTest;
{$mode objfpc}{$H+}
uses SysUtils, UIni, UParty;
var Info: TParty_ModeInfo; Rounds: ARounds; Team: integer;
procedure Check(Value: boolean; const Message_: string);
begin
  if not Value then raise Exception.Create(Message_);
end;
begin
  Ini := TIni.Create;
  Party := TPartyGame.Create;
  try
    Party.DefaultModeInfo(Info);
    Info.Name := 'Duel'; Party.RegisterMode(Info);
    Info.Name := 'CustomFullSong'; Party.RegisterMode(Info);
    Info.Name := 'SharedSingers'; Info.PlayerCount := 2; Party.RegisterMode(Info);
    for Team := 0 to 1 do
    begin
      Party.AddTeam('Team ' + IntToStr(Team));
      Party.AddPlayer(Team, 'Singer ' + IntToStr(Team));
    end;
    SetLength(Rounds, 1); Rounds[0] := 0;
    Check(Party.StartGame(Rounds), 'Start test round');
    Ini.PartyHighscores := 0;
    Check(not Party.LocalHighscoresEnabled, 'Nothing must save no Party scores');
    Ini.PartyHighscores := 1;
    Check(Party.LocalHighscoresEnabled, 'Regular Duel must be eligible');
    Party.Rounds[0].Mode := 1;
    Check(not Party.LocalHighscoresEnabled, 'Duels-only must reject other modes');
    Ini.PartyHighscores := 2;
    Check(Party.LocalHighscoresEnabled, 'Full songs need no plugin opt-in');
    Check(Party.CurrentSingerName(0) = 'Singer 0', 'Credit the actual singer');
    Party.Rounds[0].Mode := 2;
    Check(not Party.LocalHighscoresEnabled, 'Shared singers are not individual scores');
    Party.Rounds[0].Mode := -1;
    Check(not Party.LocalHighscoresEnabled, 'Invalid mode must not save');
    Party.Clear;
    Check(not Party.LocalHighscoresEnabled, 'Inactive Party must not save');
    WriteLn('PASS: three Party highscore policies, custom modes and singer identity');
  finally
    Party.Free; Party := nil;
    Ini.Free; Ini := nil;
  end;
end.
