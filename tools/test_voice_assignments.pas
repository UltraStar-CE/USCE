program TestVoiceAssignments;
{$MODE Delphi}
uses UVoiceAssignments;
var
  Assignments: TVoiceAssignments;
  SongA, SongB: TObject;
  I: integer;
procedure Check(Condition: boolean);
begin
  if not Condition then Halt(1);
end;
begin
  Assignments := TVoiceAssignments.Create;
  SongA := TObject.Create;
  SongB := TObject.Create;
  try
    Assignments.SelectSong(SongA);
    for I := 0 to 23 do Check(Assignments.VoiceForPlayer(I, 2) = I mod 2);
    Assignments.SetVoice(0, 1, 2);
    Assignments.SetVoice(1, 1, 2);
    Check(Assignments.VoiceForPlayer(0, 2) = 1);
    Check(Assignments.VoiceForPlayer(1, 2) = 1);
    Assignments.SelectSong(SongA);
    Check(Assignments.VoiceForPlayer(0, 2) = 1);
    Assignments.Rotate(2);
    Check(Assignments.VoiceForPlayer(0, 2) = 0);
    Check(Assignments.VoiceForPlayer(1, 2) = 0);
    Assignments.SetVoice(1, 1, 2);
    Check(Assignments.VoiceForPlayer(1, 2) = 1);
    Assignments.Rotate(2);
    Check(Assignments.VoiceForPlayer(0, 2) = 1);
    Check(Assignments.VoiceForPlayer(1, 2) = 0);
    Assignments.SelectSong(SongB);
    for I := 0 to 23 do Check(Assignments.VoiceForPlayer(I, 2) = I mod 2);
    Assignments.SetVoice(0, 23, 24);
    Assignments.Rotate(24);
    Check(Assignments.VoiceForPlayer(0, 24) = 0);
    Check(Assignments.VoiceForPlayer(23, 24) = 0);
    Check(Assignments.VoiceForPlayer(0, 1) = 0);
    Assignments.Reset;
    Check(Assignments.VoiceForPlayer(0, 24) = 0);
    WriteLn('Voice assignment tests passed');
  finally
    Assignments.Free;
    SongA.Free;
    SongB.Free;
  end;
end.
