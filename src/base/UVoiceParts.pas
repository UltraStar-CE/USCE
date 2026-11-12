unit UVoiceParts;
{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

interface

const
  SongVoicesPerScreen = 12;
  SupportedSongVoices = 2 * SongVoicesPerScreen;

type
  TVoiceScreenMasks = array of byte;

function TryParseVoiceMarker(const Marker: string; out VoiceNumber: integer): boolean;
procedure GetVoiceGrid(VoiceCount: integer; out Columns, RowsPerBank: integer);
function FitVoiceScreens(const Assigned: TVoiceScreenMasks; ScreenCount: integer): TVoiceScreenMasks;

implementation

uses SysUtils, Math;

function TryParseVoiceMarker(const Marker: string; out VoiceNumber: integer): boolean;
var
  Number: string;
  I: integer;
begin
  Result := false;
  VoiceNumber := 0;
  if (Length(Marker) < 2) or (Marker[1] <> 'P') then Exit;
  Number := Trim(Copy(Marker, 2, MaxInt));
  if Number = '' then Exit;
  for I := 1 to Length(Number) do
    if not (Number[I] in ['0'..'9']) then Exit;
  Result := TryStrToInt(Number, VoiceNumber) and (VoiceNumber > 0);
end;

procedure GetVoiceGrid(VoiceCount: integer; out Columns, RowsPerBank: integer);
begin
  if VoiceCount <= 0 then
  begin
    Columns := 0;
    RowsPerBank := 0;
    Exit;
  end;
  if VoiceCount <= 4 then Columns := 1
  else Columns := Ceil(Sqrt(VoiceCount / 2));
  RowsPerBank := (VoiceCount + 2 * Columns - 1) div (2 * Columns);
end;

function FitVoiceScreens(const Assigned: TVoiceScreenMasks; ScreenCount: integer): TVoiceScreenMasks;
var
  Count: array[0..1] of integer;
  Voice, Screen: integer;
  ScreenBit: byte;
begin
  Result := nil;
  SetLength(Result, Length(Assigned));
  Count[0] := 0;
  Count[1] := 0;
  // Reserve places for singers' assigned parts before showing unused parts.
  for Screen := 0 to ScreenCount - 1 do
  begin
    ScreenBit := 1 shl Screen;
    for Voice := 0 to High(Assigned) do
      if (Assigned[Voice] and ScreenBit) <> 0 then
      begin
        Result[Voice] := Result[Voice] or ScreenBit;
        Inc(Count[Screen]);
        if Count[Screen] = SongVoicesPerScreen then Break;
      end;
  end;
  for Voice := 0 to High(Assigned) do
    if Assigned[Voice] = 0 then
    begin
      Screen := 0;
      if (ScreenCount = 2) and (Count[1] < Count[0]) then Screen := 1;
      if Count[Screen] = SongVoicesPerScreen then Break;
      Result[Voice] := 1 shl Screen;
      Inc(Count[Screen]);
    end;
end;

end.
