program ImageFitTest;
{$mode delphi}
uses SysUtils, Math, UImageFit;

var Target, Actual: TImageFitRect; Checks: integer;

procedure Expect(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

procedure Near(Value, Expected: double; const Message: string);
begin
  Expect(Abs(Value - Expected) < 0.002, Message);
end;

procedure Fit(SourceW, SourceH, PixelW, PixelH: single; Upscale: boolean);
var ScaleX, ScaleY: single;
begin
  ScaleX := PixelW / 800; ScaleY := PixelH / 600;
  Expect(FitImageInside(SourceW, SourceH, ScaleX, ScaleY, Target, Actual, Upscale), 'Valid image rejected');
  Near(Actual.W * ScaleX / (Actual.H * ScaleY), SourceW / SourceH, 'Source aspect distorted');
  Near(Actual.X + Actual.W / 2, Target.X + Target.W / 2, 'Horizontal center changed');
  Near(Actual.Y + Actual.H / 2, Target.Y + Target.H / 2, 'Vertical center changed');
  Expect((Actual.W <= Target.W + 0.002) and (Actual.H <= Target.H + 0.002), 'Image escaped target');
  if not Upscale then
    Expect((Actual.W * ScaleX <= SourceW + 0.002) and
      (Actual.H * ScaleY <= SourceH + 0.002), 'Small image was enlarged');
  Inc(Checks);
end;

const
  Sources: array[0..4, 0..1] of integer =
    ((320,240), (800,600), (1600,900), (3200,600), (600,1200));
  // The 1920x1080 case is also one viewport of a 3840x1080 two-screen window.
  Viewports: array[0..4, 0..1] of integer =
    ((800,600), (1024,768), (1280,720), (2560,1080), (1920,1080));
var I, J: integer;
begin
  Target.X := 0; Target.Y := 0; Target.W := 800; Target.H := 600;
  Fit(1600,900,1024,768,false);
  Near(Actual.W,800,'Wide image did not fit width');
  Near(Actual.H,450,'Wide image height was clamped instead of scaled');
  Near(Actual.Y,75,'Vertical padding missing');
  Fit(320,240,1280,720,false);
  Near(Actual.W * 1.6,320,'Small image width enlarged');
  Near(Actual.H * 1.2,240,'Small image height enlarged');
  Expect((Actual.X > 0) and (Actual.Y > 0), 'Both-axis padding missing');
  Fit(800,600,1280,720,true);
  Near(Actual.W,600,'Default edge extension no longer permits uniform enlargement');
  Near(Actual.H,600,'Default image did not fit target height');
  for I := Low(Sources) to High(Sources) do
    for J := Low(Viewports) to High(Viewports) do
    begin
      Fit(Sources[I,0],Sources[I,1],Viewports[J,0],Viewports[J,1],false);
      Fit(Sources[I,0],Sources[I,1],Viewports[J,0],Viewports[J,1],true);
    end;
  // Motion offsets an enlarged target canvas, without stretching its image.
  Target.X := -120; Target.Y := -90; Target.W := 1040; Target.H := 780;
  Fit(800,600,2560,1080,false);
  Expect(not FitImageInside(0,600,1,1,Target,Actual), 'Zero source width accepted');
  Expect(not FitImageInside(800,600,0,1,Target,Actual), 'Zero viewport scale accepted');
  Target.H := 0;
  Expect(not FitImageInside(800,600,1,1,Target,Actual), 'Zero target height accepted');
  Writeln(Checks, ' image fitting cases passed');
end.
