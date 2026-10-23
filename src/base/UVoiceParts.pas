unit UVoiceParts;
{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

interface

const
  SupportedSongVoices = 8;

function TryParseVoiceMarker(const Marker: string; out VoiceNumber: integer): boolean;
procedure GetVoiceGrid(VoiceCount: integer; out Columns, RowsPerBank: integer);

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

end.
