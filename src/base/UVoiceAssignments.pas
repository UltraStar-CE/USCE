unit UVoiceAssignments;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

interface

type
  TVoiceAssignments = class
  private
    FSong: TObject;
    FVoices: array of integer;
    FRotation: integer;
  public
    procedure SelectSong(Song: TObject);
    procedure Reset;
    function VoiceForPlayer(PlayerIndex, VoiceCount: integer): integer;
    procedure SetVoice(PlayerIndex, Voice, VoiceCount: integer);
    procedure Rotate(VoiceCount: integer);
  end;

var
  VoiceAssignments: TVoiceAssignments;

implementation

procedure TVoiceAssignments.Reset;
begin
  FSong := nil;
  SetLength(FVoices, 0);
  FRotation := 0;
end;

procedure TVoiceAssignments.SelectSong(Song: TObject);
begin
  if FSong = Song then Exit;
  Reset;
  FSong := Song;
end;

function TVoiceAssignments.VoiceForPlayer(PlayerIndex, VoiceCount: integer): integer;
begin
  Result := 0;
  if (PlayerIndex < 0) or (VoiceCount <= 1) then Exit;
  if (PlayerIndex < Length(FVoices)) and (FVoices[PlayerIndex] >= 0) then
    Result := (FVoices[PlayerIndex] + FRotation) mod VoiceCount
  else
    Result := (PlayerIndex + FRotation) mod VoiceCount;
end;

procedure TVoiceAssignments.SetVoice(PlayerIndex, Voice, VoiceCount: integer);
var
  I, OldCount: integer;
begin
  if (PlayerIndex < 0) or (VoiceCount < 1) or
    (Voice < 0) or (Voice >= VoiceCount) then Exit;
  OldCount := Length(FVoices);
  if PlayerIndex >= OldCount then
  begin
    SetLength(FVoices, PlayerIndex + 1);
    for I := OldCount to High(FVoices) do FVoices[I] := -1;
  end;
  FVoices[PlayerIndex] := (Voice - (FRotation mod VoiceCount) + VoiceCount) mod VoiceCount;
end;

procedure TVoiceAssignments.Rotate(VoiceCount: integer);
begin
  if VoiceCount > 1 then FRotation := (FRotation + 1) mod VoiceCount;
end;

initialization
  VoiceAssignments := TVoiceAssignments.Create;
finalization
  VoiceAssignments.Free;
end.
