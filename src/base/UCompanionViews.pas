unit UCompanionViews;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses fpjson;

type
  TCompanionView = (cvFull, cvCatalog, cvRadio);

const
  CompanionViewNames: array[TCompanionView] of string = ('full', 'catalog', 'radio');
  AllCompanionViews = 7;

function CompanionViewFromName(const Name: string): TCompanionView;
function CompanionViewsJson(Policy: LongInt): TJSONObject;

implementation

uses SysUtils;

function CompanionViewFromName(const Name: string): TCompanionView;
var View: TCompanionView;
begin
  for View := Low(TCompanionView) to High(TCompanionView) do
    if SameText(Name, CompanionViewNames[View]) then Exit(View);
  Result := cvFull;
end;

function CompanionViewsJson(Policy: LongInt): TJSONObject;
var View: TCompanionView;
    Enabled: TJSONArray;
begin
  Result := TJSONObject.Create;
  Enabled := TJSONArray.Create;
  Result.Add('enabled', Enabled);
  for View := Low(TCompanionView) to High(TCompanionView) do
    if (Policy and (1 shl Ord(View))) <> 0 then Enabled.Add(CompanionViewNames[View]);
  Result.Add('default', CompanionViewNames[TCompanionView(Policy shr 3)]);
end;

end.
