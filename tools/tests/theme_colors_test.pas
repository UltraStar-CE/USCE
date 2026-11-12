program ThemeColorsTest;
{$mode objfpc}{$H+}
uses SysUtils, UThemes;
var R, G, B: real;
begin
  SetLength(Color, 2);
  Color[0].Name := 'white';
  Color[0].RGB.R := 0.25;
  Color[0].RGB.G := 0.5;
  Color[0].RGB.B := 0.75;
  Color[1].Name := 'Blue';
  if (ColorExists('White') <> 0) or (ColorExists('WHITE') <> 0) or
     (ColorExists('blue') <> 1) or (ColorExists('missing') <> -1) then
    raise Exception.Create('Theme color lookup must match INI key casing rules');
  R := 1; G := 1; B := 1;
  LoadColor(R, G, B, 'White');
  if (R <> 0.25) or (G <> 0.5) or (B <> 0.75) then
    raise Exception.Create('Inherited color reference lost its override');
  LoadColor(R, G, B, 'missing');
  if (R <> 0.25) or (G <> 0.5) or (B <> 0.75) then
    raise Exception.Create('Unknown color changed the fallback');
  WriteLn('PASS: mixed-case inherited colors and missing-color fallback');
end.
