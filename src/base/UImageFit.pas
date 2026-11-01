// SPDX-License-Identifier: GPL-2.0-or-later
unit UImageFit;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

type
  TImageFitRect = record
    X, Y, W, H: single;
  end;

// Coordinates are logical; source dimensions and the scale limit are pixels.
function FitImageInside(SourceW, SourceH, ScaleX, ScaleY: single;
  const Target: TImageFitRect; out Fitted: TImageFitRect;
  AllowUpscale: boolean = true): boolean;

implementation

uses Math;

function FitImageInside(SourceW, SourceH, ScaleX, ScaleY: single;
  const Target: TImageFitRect; out Fitted: TImageFitRect;
  AllowUpscale: boolean): boolean;
var Scale: double;
begin
  Fitted := Target;
  Result := (SourceW > 0) and (SourceH > 0) and
    (ScaleX > 0) and (ScaleY > 0) and (Target.W > 0) and (Target.H > 0);
  if not Result then Exit;
  Scale := Min(Target.W * ScaleX / SourceW, Target.H * ScaleY / SourceH);
  if not AllowUpscale then Scale := Min(Scale, 1.0);
  Fitted.W := SourceW * Scale / ScaleX;
  Fitted.H := SourceH * Scale / ScaleY;
  Fitted.X := Target.X + (Target.W - Fitted.W) / 2;
  Fitted.Y := Target.Y + (Target.H - Fitted.H) / 2;
end;

end.
