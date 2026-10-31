{ SPDX-License-Identifier: GPL-2.0-or-later }
unit UOptionModel;
{$IFDEF FPC}{$MODE Delphi}{$ENDIF}
interface
type
  TOptionKind = (okSelect, okButton, okSection);
  TOptionModel = class
  private
    Data: ^integer;
    function GetSelected: integer;
    procedure SetSelected(Value: integer);
  public
    Key: UTF8String;
    Kind: TOptionKind;
    Visible: boolean;
    InlineChoices: boolean;
    Values: array of UTF8String;
    constructor Create(const AKey: UTF8String; AKind: TOptionKind);
    procedure Bind(var AData: integer; const AValues: array of UTF8String);
    function CurrentText: UTF8String;
    property Selected: integer read GetSelected write SetSelected;
  end;
implementation
uses Math;
constructor TOptionModel.Create(const AKey: UTF8String; AKind: TOptionKind);
begin
  inherited Create;
  Key := AKey;
  Kind := AKind;
  Visible := true;
end;
procedure TOptionModel.Bind(var AData: integer; const AValues: array of UTF8String);
var I: integer;
begin
  Data := @AData;
  SetLength(Values, Length(AValues));
  for I := 0 to High(AValues) do Values[I] := AValues[I];
  Selected := AData;
end;
function TOptionModel.GetSelected: integer;
begin
  if Data = nil then Result := 0 else Result := Data^;
end;
procedure TOptionModel.SetSelected(Value: integer);
begin
  if Data <> nil then Data^ := EnsureRange(Value, 0, Max(0, High(Values)));
end;
function TOptionModel.CurrentText: UTF8String;
begin
  if (Selected >= 0) and (Selected < Length(Values)) then Result := Values[Selected]
  else Result := '';
end;
end.
