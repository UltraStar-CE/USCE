{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/base/UDraw.pas $
 * $Id: UDraw.pas 2514 2010-06-13 10:57:33Z tobigun $
 *}

unit UDraw;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UThemes,
  sdl2,
  UGraphicClasses,
  UIni,
  UPlayerLayout;

procedure SingDraw;
procedure SingDrawLines;
procedure SingDrawBackground;
procedure SingDrawOscilloscopes;
procedure SingDrawOscilloscope(Position: TThemePosition; NrSound: integer);
procedure SingDrawNoteLines(Left, Top, Right: real; LineSpacing: integer = 15; LineThickness: single = 1);
procedure SingDrawLyricHelper(CP: integer; Left, LyricsMid, IndicatorOffset: real);
procedure SingDrawLine(Left, Top, Right: real; Track, PlayerIndex: integer; LineSpacing: integer = 15);
procedure SingDrawPlayerLine(Left, Top, W: real; Track, PlayerIndex: integer; LineSpacing: integer = 15; OnlyGaps: boolean = false);
procedure SingDrawPlayerBGLine(Left, Top, Right: real; Track, PlayerIndex: integer; LineSpacing: integer = 15);

//Draw Editor NoteLines
procedure EditDrawBackgroundVoices(X, YBaseNote, W, H: real; SelectedTrack, VoiceCount: integer);
procedure EditDrawLine(X, YBaseNote, W, H: real; Track: integer; NumLines: integer = 10);
procedure EditDrawBorderedBox(X, Y, W, H: integer; FillR: real = 0.9; FillG: real = 0.9; FillB: real = 0.9; FillAlpha: real = 0.5);
procedure EditDrawBeatDelimiters(X, Y, W, H: real; Track: integer);


// Draw Webcam
procedure SingDrawWebCamFrame;

type
  TRecR = record
    Top:    real;
    Left:   real;
    Right:  real;
    Bottom: real;

    Width:  real;
    WMid:   real;
    Height: real;
    HMid:   real;
    Mid:    real;
  end;

const
P1_INVERTED = 99;

var
  NotesW:   array [0..UIni.IMaxPlayerCount-1] of real;
  NotesH:   array [0..UIni.IMaxPlayerCount-1] of real;
  Starfr:   integer;
  StarfrG:  integer;

  //SingBar
  TickOld:  cardinal;
  TickOld2: cardinal;

  FrameThread:  PSDL_Thread;
  Mutex:        PSDL_Mutex;

implementation

uses UMenuBackground,
  SysUtils,
  Math,
  UText,
  UGraphic,
  ULog,
  ULyrics,
  UNote,
  UParty,
  UMusic,
  URecord,
  URenderer,
  UScreenSingController,
  USong,
  UWebcam;

function NoteAlpha(NoteType: TNoteType; Alpha: real): real; inline;
begin
  if NoteType = ntFreestyle then
    Result := Alpha * Theme.Sing.FreestyleNoteAlpha
  else
    Result := Alpha;
end;


procedure SingDrawWebCamFrame;
begin
  if TMenuBackground.SuppressDrawing then Exit;

  Webcam.GetWebcamFrame;

  if (Webcam.TextureCam <> nil) then
  begin
    with Webcam.TextureCam do
    begin
      X := 0;
      Y := 0;
      Z := 0;
      W := RenderW;
      H := renderH;
    end;
    Renderer.DrawTexture(Webcam.TextureCam);

  end;

  {
  // Save Frame to AVI
  if (ScreenSing.WebcamSave) then
  begin
    cvCvtColor(WebcamFrame, WebcamFrame, CV_RGB2BGR);
    //cvInvert(WebcamFrame, WebcamFrame, 0);
    cvWriteFrame(ScreenSing.WebCamVideoWriter, WebcamFrame);
  end;
  }

end;

procedure SingDrawBackground;
var
  Rec:    TRecR;
  TexRec: TRecR;
  // TODO: these (especially the aspects) should just be precomputed
  ScreenAspect: double;  // aspect of screen resolution and image
  ScaledTexWidth, ScaledTexHeight: double;
begin
  if TMenuBackground.SuppressDrawing then Exit;
  // TODO: this is also called if a video is playing
  if (ScreenSing.Tex_Background <> nil) then
  begin
    if (Ini.MovieSize <= 1) then  //HalfSize BG
    begin
      (* half screen + gradient *)
      Rec.Top := 110; // 80
      Rec.Bottom := Rec.Top + 20;
      Rec.Left  := 0;
      Rec.Right := RenderW;

      TexRec.Top := (Rec.Top / RenderH);
      TexRec.Bottom := (Rec.Bottom / RenderH);
      TexRec.Left := 0;
      TexRec.Right := 1;

      (* gradient draw *)
      (* top *)
      with ScreenSing.Tex_Background do
      begin
        X := Rec.Left;
        Y := Rec.Top;
        W := Rec.Right - Rec.Left;
        H := Rec.Bottom - Rec.Top;
        TexX1 := TexRec.Left;
        TexX2 := TexRec.Right;
        TexY1 := TexRec.Top;
        TexY2 := TexRec.Bottom;
        AlphaGradient := gdVertical;
        Alpha := 0; // Top alpha
        Alpha2 := 1; // Bottom alpha
      end;
      Renderer.DrawTexture(ScreenSing.Tex_Background);

      (* mid *)
      Rec.Top := Rec.Bottom;
      Rec.Bottom := 490 - 20; // 490 - 20
      TexRec.Top := TexRec.Bottom;
      TexRec.Bottom := (Rec.Bottom / RenderH);
      with ScreenSing.Tex_Background do
      begin
        Y := Rec.Top;
        H := Rec.Bottom - Rec.Top;
        TexY1 := TexRec.Top;
        TexY2 := TexRec.Bottom;
        AlphaGradient := gdNone;
        Alpha := 1;
      end;
      Renderer.DrawTexture(ScreenSing.Tex_Background);

      (* bottom *)
      Rec.Top := Rec.Bottom;
      Rec.Bottom := 490; // 490
      TexRec.Top := TexRec.Bottom;
      TexRec.Bottom := (Rec.Bottom / RenderH);
      with ScreenSing.Tex_Background do
      begin
        Y := Rec.Top;
        H := Rec.Bottom - Rec.Top;
        TexY1 := TexRec.Top;
        TexY2 := TexRec.Bottom;
        AlphaGradient := gdVertical;
        Alpha := 1; // Top alpha
        Alpha2 := 0; // Bottom alpha
      end;
      Renderer.DrawTexture(ScreenSing.Tex_Background);
    end
    else //Full Size BG
    begin
      // Three aspects to take into account:
      //  1. Screen/display resolution (e.g. 1920x1080 -> 16:9)
      //  2. Render aspect (fWidth x fHeight -> variable)
      //  3. Movie aspect (video frame aspect stored in fAspect)
      ScreenAspect := ScreenWPerScreen / ScreenH;

      case ScreenSing.PictureAspectCorrection of
        acoCrop: begin
          if (ScreenAspect >= ScreenSing.Tex_BackgroundAspectRatio) then
          begin
            ScaledTexWidth  := RenderW;
            ScaledTexHeight := RenderH * ScreenAspect/ScreenSing.Tex_BackgroundAspectRatio;
          end else
          begin
            ScaledTexHeight := RenderH;
            ScaledTexWidth  := RenderW * ScreenSing.Tex_BackgroundAspectRatio/ScreenAspect;
          end;
        end;

        acoHalfway: begin
          ScaledTexWidth  := (RenderW + RenderW * ScreenSing.Tex_BackgroundAspectRatio/ScreenAspect)/2;
          ScaledTexHeight := (RenderH + RenderH * ScreenAspect/ScreenSing.Tex_BackgroundAspectRatio)/2;
        end;

        acoLetterBox: begin
          if (ScreenAspect <= ScreenSing.Tex_BackgroundAspectRatio) then
          begin
            ScaledTexWidth  := RenderW;
            ScaledTexHeight := RenderH * ScreenAspect/ScreenSing.Tex_BackgroundAspectRatio;
          end else
          begin
            ScaledTexHeight := RenderH;
            ScaledTexWidth  := RenderW * ScreenSing.Tex_BackgroundAspectRatio/ScreenAspect;
          end;
        end else
          raise Exception.Create('Unhandled aspect correction!');
      end;

      //center video
      Rec.Left  := (RenderW - ScaledTexWidth) / 2;
      Rec.Right := Rec.Left + ScaledTexWidth;
      Rec.Top := (RenderH - ScaledTexHeight) / 2;
      Rec.Bottom := Rec.Top + ScaledTexHeight;
      with ScreenSing.Tex_Background do
      begin
        X := Rec.Left;
        Y := Rec.Top;
        W := Rec.Right - Rec.Left;
        H := Rec.Bottom - Rec.Top;
        TexX1 := 0;
        TexX2 := 1;
        TexY1 := 0;
        TexY2 := 1;
        AlphaGradient := gdNone;
        Alpha := 1;
      end;
      Renderer.DrawTexture(ScreenSing.Tex_Background);
    end;
  end;
end;


procedure SingDrawOscilloscopes;
  function GetBaseOscilloscopePosition: TThemePosition;
  begin
    Result := Theme.Sing.PlayerTemplate.Oscilloscope;
  end;
  procedure GetLaneLayout(const PlayerCountOnScreen, PlayerIndexOnScreen: integer;
    out LaneLeft, LaneTop, LaneWidth: integer);
  var
    Layout: TSingLaneLayout;
  begin
    Layout := GetSingLaneLayout(PlayerCountOnScreen, PlayerIndexOnScreen, Theme.Sing.PlayerLayout,
      CurrentSong.isDuet);
    LaneLeft := Layout.ColumnLeft;
    LaneTop := Layout.RowAnchorY;
    LaneWidth := Layout.ColumnWidth;
  end;
  function GetOscilloscopePosition(PlayerIndex: integer): TThemePosition;
  var
    BasePosition: TThemePosition;
    LocalPlayerCount: integer;
    LocalIndex: integer;
    LaneLeft: integer;
    LaneTop: integer;
    LaneWidth: integer;
    Scale: real;
    GroupTop: integer;
    Layout: TSingLaneLayout;
  begin
    if Screens > 1 then
    begin
      LocalPlayerCount := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
      LocalIndex := GetPlayerIndexOnScreen(PlayerIndex, PlayersPlay, Screens);
    end
    else
    begin
      LocalPlayerCount := PlayersPlay;
      LocalIndex := PlayerIndex;
    end;

    BasePosition := GetBaseOscilloscopePosition;
    Layout := GetSingLaneLayout(LocalPlayerCount, LocalIndex, Theme.Sing.PlayerLayout,
      CurrentSong.isDuet);
    GetLaneLayout(LocalPlayerCount, LocalIndex, LaneLeft, LaneTop, LaneWidth);
    Scale := Layout.WidgetScale;

    GroupTop := Max(10, LaneTop -
      GetSingHeaderTopOffset(Theme.Sing.PlayerWidgetLayout, Layout.GridRows, Scale));

    Result := BasePosition;
    Result.W := Max(Theme.Sing.PlayerWidgetLayout.OscilloscopeMinW, Round(BasePosition.W * Scale));
    Result.H := Max(Theme.Sing.PlayerWidgetLayout.OscilloscopeMinH, Round(BasePosition.H * Scale));
    Result.X := GetSingPlayerWidgetX(BasePosition.X, BasePosition.W, Result.W,
      LaneLeft, LaneWidth, Theme.Sing.PlayerWidgetLayout.OscilloscopeAnchorX,
      Scale, Theme.Sing.PlayerWidgetLayout);
    Result.Y := GetSingPlayerWidgetY(BasePosition.Y, GroupTop, Scale,
      Theme.Sing.PlayerWidgetLayout);
  end;
var
  PlayerIndex: integer;
begin;
  for PlayerIndex := 0 to PlayersPlay - 1 do
    if (Screens <= 1) or (GetPlayerScreen(PlayerIndex, PlayersPlay, Screens) = ScreenAct) then
      SingDrawOscilloscope(GetOscilloscopePosition(PlayerIndex), PlayerIndex);
end;

procedure SingDrawOscilloscope(Position: TThemePosition; NrSound: integer);
var
  SampleIndex, PointIndex: integer;
  Sound:       TCaptureBuffer;
  MaxX, MaxY:  real;
  Col: TRGB;
  PointList: TPointList;
const
  SampleIndexStep = 32;
begin;
  Sound := AudioInputProcessor.Sound[NrSound];

  if (Party.bPartyGame) then
    Col := GetPlayerColor(Ini.TeamColor[NrSound])
  else
    Col := GetPlayerColor(Ini.PlayerColor[NrSound]);

  MaxX := Position.W-1;
  MaxY := (Position.H-1) / 2;
  Sound.LockAnalysisBuffer();
  SetLength(PointList, (Length(Sound.AnalysisBuffer) + SampleIndexStep - 1) div SampleIndexStep);

  for PointIndex := 0 to High(PointList) do
  begin
    SampleIndex := PointIndex * SampleIndexStep;
    PointList[PointIndex].X := SampleIndex;
    PointList[PointIndex].Y := Sound.AnalysisBuffer[SampleIndex];
  end;

  Sound.UnlockAnalysisBuffer();
  Renderer.DrawLineStrip(PointList, MaxX/High(Sound.AnalysisBuffer), MaxY/Low(Smallint), Position.X, Position.Y + MaxY, Col.R, Col.G, Col.B, 1);
end;

procedure SingDrawNoteLines(Left, Top, Right: real; LineSpacing: integer; LineThickness: single);
var
  Count: integer;
  Y: single;
begin
  for Count := 0 to 9 do
  begin
    Y := Top + Count * LineSpacing;
    Renderer.DrawLine(Left, Y, Right, Y, 0, LineThickness, Skin_P1_LinesR, Skin_P1_LinesG, Skin_P1_LinesB, Theme.Sing.GuideAlpha);
  end;
end;

// draw blank Notebars
procedure SingDrawLine(Left, Top, Right: real; Track, PlayerIndex: integer; LineSpacing: integer);
var
  Rec:   TRecR;
  Count: integer;
  TempR: real;
  PlayerNumber: integer;
  Texture: TTexture;
  ColorR, ColorG, ColorB, A: single;
  GoldenStarPos: real;
begin
  if (ScreenSing.settings.NotesVisible[Track]) then
  begin
    // the textures start counting at 1, but everything else just starts at 0
    PlayerNumber := PlayerIndex + 1;

    if not CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].HasLength(TempR) then TempR := 0
    else TempR := (Right-Left) / TempR;

    with CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine] do
    begin
      for Count := 0 to HighNote do
      begin
        with Notes[Count] do
        begin
          If IsUnpitchedNote(NoteType) then
              Texture := Tex_plain_Left_Rap[PlayerNumber]
            else
              Texture := Tex_plain_Left[PlayerNumber];
            if Ini.EffectSing = 0 then
              // If Golden note Effect of then Change not Color
            begin
              case NoteType of
                ntNormal:
                begin
                  ColorR := 1;
                  ColorG := 1;
                  ColorB := 1;
                  A := 1; // We set alpha to 1, cause we can control the transparency through the png itself
                end;
                ntGolden:
                begin
                  ColorR := 1;
                  ColorG := 1;
                  ColorB := 0.3;
                  A := 1; // no stars, paint yellow -> glColor4f(1, 1, 0.3, 0.85); - we could
                end;
                ntFreestyle, ntRap:
                begin
                  ColorR := 1;
                  ColorG := 1;
                  ColorB := 1;
                  A := 1;
                end;
                ntRapGolden:
                begin
                  ColorR := 1;
                  ColorG := 1;
                  ColorB := 0.3;
                  A := 1;
                end;
              end; // case
            end //Else all Notes same Color
            else
            begin
              ColorR := 1;
              ColorG := 1;
              ColorB := 1;
              A := 1;
            end;

            A := NoteAlpha(NoteType, A);

            // left part
            Rec.Left  := (StartBeat - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat) * TempR + Left + 0.5;
            Rec.Right := Rec.Left + NotesW[PlayerIndex];
            Rec.Top := Top - (DisplayTone-BaseNote)*LineSpacing/2 - NotesH[PlayerIndex];
            Rec.Bottom := Rec.Top + 2 * NotesH[PlayerIndex];
            with Texture do
            begin
              X := Rec.Left;
              Y := Rec.Top;
              W := Rec.Right - Rec.Left;
              H := Rec.Bottom - Rec.Top;
              ColR := ColorR;
              ColG := ColorG;
              ColB := ColorB;
              Alpha := A;
            end;
            Renderer.DrawTexture(Texture);

            //We keep the postion of the top left corner b4 it's overwritten
            GoldenStarPos := Rec.Left;
            //done

            // middle part
            Rec.Left := Rec.Right;
            Rec.Right := (StartBeat + Duration - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat) * TempR + Left - NotesW[PlayerIndex] - 0.5;

            // the left note is more right than the right note itself, sounds weird - so we fix that xD
            if Rec.Right <= Rec.Left then
              Rec.Right := Rec.Left;

            If IsUnpitchedNote(NoteType) then
              Texture := Tex_plain_Mid_Rap[PlayerNumber]
            else
              Texture := Tex_plain_Mid[PlayerNumber];

            with Texture do
            begin
              X := Rec.Left;
              Y := Rec.Top;
              W := Rec.Right - Rec.Left;
              H := Rec.Bottom - Rec.Top;
              ColR := ColorR;
              ColG := ColorG;
              ColB := ColorB;
              Alpha := A;
              TexX1 := 0;
              TexX2 := round((Rec.Right-Rec.Left)/32);
              TexY1 := 0;
              TexY2 := 1;
            end;
            Renderer.DrawTexture(Texture);

            // right part
            Rec.Left  := Rec.Right;
            Rec.Right := Rec.Right + NotesW[PlayerIndex];


            if IsUnpitchedNote(NoteType) then
              Texture := Tex_plain_Right_Rap[PlayerNumber]
            else
              Texture := Tex_plain_Right[PlayerNumber];
            with Texture do
            begin
              X := Rec.Left;
              Y := Rec.Top;
              W := Rec.Right - Rec.Left;
              H := Rec.Bottom - Rec.Top;
              ColR := ColorR;
              ColG := ColorG;
              ColB := ColorB;
              Alpha := A;
            end;
            Renderer.DrawTexture(Texture);

            // Golden Star Patch
            if ((NoteType = ntGolden) or (NoteType = ntRapGolden)) and (Ini.EffectSing=1) and ScreenSing.Settings.FeedbackVisible then
            begin
              GoldenRec.SaveGoldenStarsRec(GoldenStarPos, Rec.Top, Rec.Right, Rec.Bottom);
            end;
        end; // with
      end; // for
    end; // with
  end;
end;

// draw sung notes
procedure SingDrawPlayerLine(Left, Top, W: real; Track, PlayerIndex: integer; LineSpacing: integer; OnlyGaps: boolean);
var
  TempR:      real;
  Rec:        TRecR;
  N: integer;
  FirstBeat, WindowStart, BaseTone: real;
  DrawingGap: boolean;
  Texture: TTexture;
//  R, G, B, A: real;
  NotesH2:    real;
  procedure DrawSungTexture;
  begin
    if DrawingGap then
    begin
      if Texture.X < Left then begin Texture.W := Texture.W-(Left-Texture.X); Texture.X := Left; end;
      Texture.W := Min(Texture.W,Left+W-Texture.X);
      if Texture.W <= 0 then Exit;
    end;
    Renderer.DrawTexture(Texture);
  end;
begin
  if (ScreenSing.Settings.InputVisible) then
  begin
    //Log.LogStatus('Player notes', 'SingDraw');

    //if Player[NrGracza].LengthNote > 0 then
    begin
      if not CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].HasLength(TempR) then TempR := 0
      else TempR := W / TempR;

      for N := 0 to Player[PlayerIndex].HighNote do
      begin
        DrawingGap := Player[PlayerIndex].Note[N].IsGap;
        if DrawingGap and (Ini.PitchTrace=0) then Continue;
        if OnlyGaps and not DrawingGap then Continue;
        with CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine] do
          if Length(Notes)>0 then begin FirstBeat:=Notes[0].StartBeat;BaseTone:=BaseNote;end
          else begin FirstBeat:=Player[PlayerIndex].DetectionBeat-15;BaseTone:=Player[PlayerIndex].LastSungTone;TempR:=W/16;end;
        WindowStart := FirstBeat;
        if DrawingGap and (TempR > 0) and
          ((Player[PlayerIndex].DetectionBeat < FirstBeat) or
           (Player[PlayerIndex].DetectionBeat >= FirstBeat+W/TempR)) then
          WindowStart := Player[PlayerIndex].DetectionBeat+1-W/TempR;
        with Player[PlayerIndex].Note[N] do
        begin
          // Left part of note
          Rec.Left  := Left + (Start - WindowStart) * TempR + 0.5;
          Rec.Right := Rec.Left + NotesW[PlayerIndex];

          // Draw it in half size, if not hit
          if DrawingGap then
          begin
            NotesH2 := Max(0.5, NotesH[PlayerIndex] * 0.5);
          end
          else if Hit then
          begin
            NotesH2 := NotesH[PlayerIndex]
          end
          else
          begin
            NotesH2 := int(NotesH[PlayerIndex] * 0.65);
          end;

          Rec.Top    := Top - (Tone-BaseTone)*LineSpacing/2 - NotesH2;
          Rec.Bottom := Rec.Top + 2 * NotesH2;

          // draw the left part
          If IsUnpitchedNote(NoteType) then
            Texture := Tex_Left_Rap[PlayerIndex+1]
          else
            Texture := Tex_Left[PlayerIndex+1];
          with Texture do
          begin
            X := Rec.Left;
            Y := Rec.Top;
            W := Rec.Right - Rec.Left;
            H := Rec.Bottom - Rec.Top;
            ColR := 1;
            ColG := 1;
            ColB := 1;
            Alpha := NoteAlpha(NoteType, 1);
          end;
          DrawSungTexture;

          // Middle part of the note
          Rec.Left  := Rec.Right;
          Rec.Right := Left + (Start + Duration - WindowStart) * TempR - NotesW[PlayerIndex] - 0.5;

          // new
          if (Start + Duration - 1 = LyricsState.CurrentBeatD) then
            Rec.Right := Rec.Right - (1-Frac(LyricsState.MidBeatD)) * TempR;

          // the left note is more right than the right note itself, sounds weird - so we fix that xD
          if Rec.Right <= Rec.Left then
            Rec.Right := Rec.Left;

          // draw the middle part
          If IsUnpitchedNote(NoteType) then
            Texture := Tex_Mid_Rap[PlayerIndex+1]
          else
            Texture := Tex_Mid[PlayerIndex+1];

          with Texture do
          begin
            X := Rec.Left;
            Y := Rec.Top;
            W := Rec.Right - Rec.Left;
            H := Rec.Bottom - Rec.Top;
            ColR := 1;
            ColG := 1;
            ColB := 1;
            Alpha := 1;
            TexX1 := 0;
            TexY1 := 0;
            TexX2 := round((Rec.Right-Rec.Left)/32);
            TexY2 := 1;
            Alpha := NoteAlpha(NoteType, 1);
          end;
          DrawSungTexture;

          // the right part of the note
          Rec.Left  := Rec.Right;
          Rec.Right := Rec.Right + NotesW[PlayerIndex];

          If IsUnpitchedNote(NoteType) then
            Texture := Tex_Right_Rap[PlayerIndex+1]
          else
            Texture := Tex_Right[PlayerIndex+1];
          with Texture do
          begin
            X := Rec.Left;
            Y := Rec.Top;
            W := Rec.Right - Rec.Left;
            H := Rec.Bottom - Rec.Top;
            ColR := 1;
            ColG := 1;
            ColB := 1;
            Alpha := NoteAlpha(NoteType, 1);
          end;
          DrawSungTexture;

          // Perfect note is stored
          if Perfect and (Ini.EffectSing=1) and ScreenSing.Settings.FeedbackVisible then
          begin
            //A := 1 - 2*(LyricsState.GetCurrentTime() - GetTimeFromBeat(Start + Duration));
            if not (Start + Duration - 1 = LyricsState.CurrentBeatD) then
            begin
              //Star animation counter
              //inc(Starfr);
              //Starfr := Starfr mod 128;
             // if not(CurrentSong.isDuet) or (PlayerIndex mod 2 = Track) then
                GoldenRec.SavePerfectNotePos(Rec.Left, Rec.Top);
            end;
          end;
        end; // with
      end; // for

      // actually we need a comparison here, to determine if the singing process
      // is ahead Rec.Right even if there is no singing

      if not OnlyGaps and (Ini.EffectSing = 1) and ScreenSing.Settings.FeedbackVisible and
         (Player[PlayerIndex].HighNote >= 0) and not Player[PlayerIndex].Note[Player[PlayerIndex].HighNote].IsGap then
        GoldenRec.GoldenNoteTwinkle(Rec.Top,Rec.Bottom,Rec.Right, PlayerIndex);
    end; // if
  end; // if
end;

//draw Note glow
procedure SingDrawPlayerBGLine(Left, Top, Right: real; Track, PlayerIndex: integer; LineSpacing: integer);
var
  Rec:            TRecR;
  Count:          integer;
  TempR:          real;
  W, H:           real;
  A:             single;
  Texture:       TTexture;
  GlowPadX:       real;
  GlowExtraW:     real;
  GlowExtraH:     real;
begin
  if (ScreenSing.settings.NotesVisible[PlayerIndex]) then
  begin
    A := sqrt((1 + sin(AudioPlayback.Position * 3)))/2 + 0.05;

    if not CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].HasLength(TempR) then TempR := 0
    else TempR := (Right-Left) / TempR;

    with CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine] do
    begin
      for Count := 0 to HighNote do
      begin
        with Notes[Count] do
        begin
          if ScoreFactor[NoteType] > 0 then
          begin
            GlowPadX := Max(1.0, NotesW[PlayerIndex] * 0.65);
            GlowExtraW := Max(1.0, NotesW[PlayerIndex] * 0.35);
            GlowExtraH := Max(1.5, NotesH[PlayerIndex] * 0.3);
            W := NotesW[PlayerIndex] * 2 + GlowExtraW;
            H := NotesH[PlayerIndex] * 1.5 + GlowExtraH;

            // left
            Rec.Right := (StartBeat - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat) * TempR + Left + 0.5 + GlowPadX;
            Rec.Left  := Rec.Right - W;
            Rec.Top := Top - (DisplayTone-BaseNote)*LineSpacing/2 - H;
            Rec.Bottom := Rec.Top + 2 * H;

            If IsUnpitchedNote(NoteType) then
              Texture := Tex_BG_Left_Rap[PlayerIndex+1]
            else
              Texture := Tex_BG_Left[PlayerIndex+1];
            with Texture do
            begin
              X := Rec.Left;
              Y := Rec.Top;
              W := Rec.Right - Rec.Left;
              H := Rec.Bottom - Rec.Top;
              Alpha := NoteAlpha(NoteType, A);
            end;
            Renderer.DrawTexture(Texture);

            // middle part
            Rec.Left  := Rec.Right;
            Rec.Right := (StartBeat + Duration - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat) * TempR + Left - 0.5 - GlowPadX;

            // the left note is more right than the right note itself, sounds weird - so we fix that xD
            if Rec.Right <= Rec.Left then
              Rec.Right := Rec.Left;

            If IsUnpitchedNote(NoteType) then
              Texture := Tex_BG_Mid_Rap[PlayerIndex+1]
            else
              Texture := Tex_BG_Mid[PlayerIndex+1];
            with Texture do
            begin
              X := Rec.Left;
              Y := Rec.Top;
              W := Rec.Right - Rec.Left;
              H := Rec.Bottom - Rec.Top;
              Alpha := NoteAlpha(NoteType, A);
            end;
            Renderer.DrawTexture(Texture);

            // right part
            Rec.Left  := Rec.Right;
            Rec.Right := Rec.Left + W;

            If IsUnpitchedNote(NoteType) then
              Texture := Tex_BG_Right_Rap[PlayerIndex+1]
            else
              Texture := Tex_BG_Right[PlayerIndex+1];
            with Texture do
            begin
              X := Rec.Left;
              Y := Rec.Top;
              W := Rec.Right - Rec.Left;
              H := Rec.Bottom - Rec.Top;
              Alpha := NoteAlpha(NoteType, A);
            end;
            Renderer.DrawTexture(Texture);

          end;
        end; // with
      end; // for
    end; // with

  end;
end;

(**
 * Draws the lyrics helper bar.
 * Left: position the bar starts at
 * LyricsMid: the middle of the lyrics relative to the position Left 
 *)
procedure SingDrawLyricHelper(CP: integer; Left, LyricsMid, IndicatorOffset: real);
var
  Bounds: TRecR;           // bounds of the lyric help bar
  BarProgress: real;       // progress of the lyrics helper
  BarMoveDelta: real;      // current beat relative to the beat the bar starts to move at
  BarAlpha: real;          // transparency
  CurLine:  PLine;         // current lyric line (beat specific)
  LineWidth: real;         // lyric line width
  FirstNoteBeat: integer;  // beat of the first note in the current line
  FirstNoteDelta: integer; // time in beats between the start of the current line and its first note
  MoveStartX: real;        // x-pos. the bar starts to move from
  MoveDist: real;          // number of pixels the bar will move
  BarWidth, BarHeight: real;
  LyricEngine: TLyricEngine;
  Col: TRGB;
const
  DefaultBarWidth  = 50; // width  of the lyric helper bar
  DefaultBarHeight = 30; // height of the lyric helper bar
  BarMoveLimit = 40; // max. number of beats remaining before the bar starts to move
begin
  // get current lyrics line and the time in beats of its first note
  CurLine := @CurrentSong.Tracks[CP].Lines[CurrentSong.Tracks[CP].CurrentLine];

  // FIXME: accessing ScreenSing is not that generic
  if (CurrentSong.isDuet) then
  begin
    LyricEngine := ScreenSing.VoiceLyrics[CP];
  end
  else
    LyricEngine := ScreenSing.Lyrics;

  BarHeight := Min(Theme.Sing.HelperHeight, LyricEngine.UpperLineH * 0.85);
  BarWidth := Theme.Sing.HelperWidth * BarHeight / Theme.Sing.HelperHeight;
  LyricEngine.FontFamily := Ini.LyricsFont;
  LyricEngine.FontStyle  := Ini.LyricsStyle;

  // do not draw the lyrics helper if the current line does not contain any note
  if (Length(CurLine.Notes) > 0) then
  begin
    // start beat of the first note of this line
    FirstNoteBeat := CurLine.Notes[0].StartBeat;
    // time in beats between the start of the current line and its first note
    FirstNoteDelta := FirstNoteBeat - CurLine.StartBeat;

    // beats from current beat to the first note of the line
    BarMoveDelta := FirstNoteBeat - LyricsState.MidBeat;

    if (FirstNoteDelta > 8) and  // if the wait-time is large enough
       (BarMoveDelta > 0) then   // and the first note of the line is not reached
    begin
      // let the bar blink to the beat
      BarAlpha := 0.75 + cos(BarMoveDelta/2) * 0.25;

      // if the number of beats to the first note is too big,
      // the bar stays on the left side.
      if (BarMoveDelta > BarMoveLimit) then
        BarMoveDelta := BarMoveLimit;

      // limit number of beats the bar moves
      if (FirstNoteDelta > BarMoveLimit) then
        FirstNoteDelta := BarMoveLimit;

      // calc bar progress
      BarProgress := 1 - BarMoveDelta / FirstNoteDelta;

      // retrieve the width of the upper lyrics line on the display
      if (LyricEngine.GetUpperLine() <> nil) then
        LineWidth := LyricEngine.GetUpperLine().Width
      else
        LineWidth := 0;

      // distance the bar will move (LyricRec.Left to beginning of text)
      MoveDist := LyricsMid - LineWidth / 2 - BarWidth;
      // if the line is too long the helper might move from right to left
      // so we have to assure the start position is left of the text.
      if (MoveDist >= 0) then
        MoveStartX := Left
      else
        MoveStartX := Left + MoveDist;

      // determine lyric help bar position and size
      Bounds.Left := MoveStartX + BarProgress * MoveDist;
      Bounds.Right := Bounds.Left + BarWidth;
      Bounds.Top := LyricEngine.UpperLineY + IndicatorOffset;

      Bounds.Bottom := Bounds.Top + BarHeight + 3;

      // draw lyric help bar
      Col := GetLyricBarColor(Ini.SingColor[CP mod UIni.IMaxPlayerCount]);

      with Tex_Lyric_Help_Bar do
      begin
        X := Bounds.Left;
        Y := Bounds.Top;
        W := Bounds.Right - Bounds.Left;
        H := Bounds.Bottom - Bounds.Top;
        ColR := Col.R;
        ColG := Col.G;
        ColB := Col.B;
        Alpha := BarAlpha;
      end;
      if Theme.Sing.HelperAbove then
      begin
        Tex_Lyric_Help_Bar.X := Left + LyricsMid - 50 * (1 - BarProgress);
        Tex_Lyric_Help_Bar.Y := LyricEngine.UpperLineY - 8;
        Tex_Lyric_Help_Bar.W := 100 * (1 - BarProgress);
        Tex_Lyric_Help_Bar.H := 4;
        Tex_Lyric_Help_Bar.ColR := Theme.Sing.LyricActive.R;
        Tex_Lyric_Help_Bar.ColG := Theme.Sing.LyricActive.G;
        Tex_Lyric_Help_Bar.ColB := Theme.Sing.LyricActive.B;
      end;
      Tex_Lyric_Help_Bar.CornerRadius := Theme.Sing.HelperRadius;
      Renderer.DrawTexture(Tex_Lyric_Help_Bar);
    end;
  end;
end;

procedure SingDrawLines;
var
  NR: TRecR;         // lyrics area bounds (NR = NoteRec?)
  PlayerIndex: integer;
  LocalIndex: integer;
  LineTop: real;
  LineSpacing: integer;
  PlayerCountOnScreen: integer;
  LaneLeft: real;
  LaneRight: real;
  procedure GetLaneLayout(const CurrentPlayerIndex: integer; out Left, Right, Top: real; out Spacing: integer);
  var
    Layout: TSingLaneLayout;
  begin
    if Screens > 1 then
    begin
      PlayerCountOnScreen := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
      LocalIndex := GetPlayerIndexOnScreen(CurrentPlayerIndex, PlayersPlay, Screens);
    end
    else
    begin
      PlayerCountOnScreen := PlayersPlay;
      LocalIndex := CurrentPlayerIndex;
    end;

    Layout := GetSingLaneLayout(PlayerCountOnScreen, LocalIndex, Theme.Sing.PlayerLayout,
      CurrentSong.isDuet);
    Left := Layout.GridLeft;
    Right := Layout.GridRight;
    Top := Layout.GuideTopY;
    Spacing := Layout.NoteLineSpacing;
  end;
begin
  // positions
  NR.Left := 20;
  NR.Right := 780;
  NR.Width := 760; //NR.Right - NR.Left;
  NR.WMid  := 380;//NR.Width / 2;
  NR.Mid   := 400;//NR.Left + NR.WMid;

  // draw note-lines

  if Ini.NoteLines <> 1 then
    Exit;

  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    if (Screens > 1) and (GetPlayerScreen(PlayerIndex, PlayersPlay, Screens) <> ScreenAct) then
      Continue;
    if not ScreenSing.Settings.NotesVisible[PlayerIndex] then
      Continue;

    GetLaneLayout(PlayerIndex, LaneLeft, LaneRight, LineTop, LineSpacing);
    SingDrawNoteLines(LaneLeft, LineTop, LaneRight, LineSpacing);
  end;
end;

procedure SingDraw;
var
  NR: TRecR;         // lyrics area bounds (NR = NoteRec?)
  LyricEngine: TLyricEngine;
  I: integer;
  Difficulty: integer;
  PlayerCountOnScreen: integer;
  PlayerIndex: integer;
  LocalIndex: integer;
  LineTop: real;
  LineSpacing: integer;
  TrackIndex: integer;
  LaneLeft: real;
  LaneRight: real;
  LaneWidth: real;
  Layout: TSingLaneLayout;
  ContentScale: real;
  BaseNoteH: real;
  BaseNoteW: real;
  procedure GetLaneLayout(const CurrentPlayerIndex: integer; out Left, Right, Width, Top: real; out Spacing: integer);
  begin
    if Screens > 1 then
    begin
      PlayerCountOnScreen := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
      LocalIndex := GetPlayerIndexOnScreen(CurrentPlayerIndex, PlayersPlay, Screens);
    end
    else
    begin
      PlayerCountOnScreen := PlayersPlay;
      LocalIndex := CurrentPlayerIndex;
    end;

    Layout := GetSingLaneLayout(PlayerCountOnScreen, LocalIndex, Theme.Sing.PlayerLayout,
      CurrentSong.isDuet);
    Left := Layout.GridLeft;
    Right := Layout.GridRight;
    Width := Right - Left;
    Top := Layout.RowAnchorY;
    Spacing := Layout.NoteLineSpacing;
  end;
begin
  // positions
  NR.Left := 20;
  NR.Right := 780;
  NR.Width := 760; //NR.Right - NR.Left;
  NR.WMid  := 380; //NR.Width / 2;
  NR.Mid   := 400; //NR.Left + NR.WMid;
  if ScreenSing.Settings.LyricsVisible then
  begin
    if CurrentSong.isDuet then
    begin
      ScreenSing.LayoutVoiceLyrics;
      for I := 0 to High(ScreenSing.DisplayedVoices) do
      begin
        ScreenSing.PositionVoiceLyrics(I);
        TrackIndex := ScreenSing.DisplayedVoices[I];
        LyricEngine := ScreenSing.VoiceLyrics[TrackIndex];
        LyricEngine.Draw(LyricsState.MidBeat);
        if ScreenSing.DisplayedVoiceBanks[I] = 0 then
          SingDrawLyricHelper(TrackIndex, LyricEngine.UpperLineX, LyricEngine.UpperLineW / 2,
            Theme.LyricBarDuetP1.IndicatorYOffset)
        else
          SingDrawLyricHelper(TrackIndex, LyricEngine.UpperLineX, LyricEngine.UpperLineW / 2,
            Theme.LyricBarDuetP2.IndicatorYOffset);
        if Theme.Sing.VoiceLabelVisible then
          with Theme.Sing.VoiceLabel do
          begin
            SetFont(Font, Style);
            SetFontSize(Size);
            if Theme.Sing.VoiceLabelUseVoiceColor then
              SetFontColor(LyricEngine.LineColor_act.R, LyricEngine.LineColor_act.G, LyricEngine.LineColor_act.B, 1)
            else SetFontColor(ColR, ColG, ColB, 1);
            SetFontPos(LyricEngine.UpperLineX - Theme.Sing.VoiceLabelGutter + X,
              LyricEngine.UpperLineY + Y);
            PrintText('P' + IntToStr(TrackIndex + 1));
          end;
      end;
    end
    else
    begin
      ScreenSing.Lyrics.Draw(LyricsState.MidBeat);
      SingDrawLyricHelper(0, NR.Left, NR.WMid, Theme.LyricBar.IndicatorYOffset);
    end;
  end;

  // oscilloscope
  if (ScreenSing.Settings.OscilloscopeVisible) then
  begin
    SingDrawOscilloscopes;
  end;

  for I := 1 to PlayersPlay do
  begin
    if (ScreenSong.Mode = smNormal) or (ScreenSong.Mode = smMedley) then
      Difficulty := Player[I - 1].Level
    else
      Difficulty := Ini.Difficulty;

    case Difficulty of
      0:
        begin
          BaseNoteH := 11;
          BaseNoteW := 6;
        end;
      1:
        begin
          BaseNoteH := 8;
          BaseNoteW := 4;
        end;
      2:
        begin
          BaseNoteH := 5;
          BaseNoteW := 3;
        end;
    else
      begin
        BaseNoteH := 8;
        BaseNoteW := 4;
      end;
    end;

    if Screens > 1 then
    begin
      PlayerCountOnScreen := GetScreenPlayerCount(PlayersPlay, Screens, ScreenAct);
      LocalIndex := GetPlayerIndexOnScreen(I - 1, PlayersPlay, Screens);
    end
    else
    begin
      PlayerCountOnScreen := PlayersPlay;
      LocalIndex := I - 1;
    end;

    Layout := GetSingLaneLayout(PlayerCountOnScreen, LocalIndex, Theme.Sing.PlayerLayout,
      CurrentSong.isDuet);
    ContentScale := Layout.ContentScale;
    NotesH[I - 1] := Max(2.0, BaseNoteH * ContentScale * Theme.Sing.NoteScale);
    NotesW[I - 1] := Max(1.0, BaseNoteW * ContentScale);
  end;

  // draw notes lines
  if (ScreenSing.Settings.InputVisible) then
    SingDrawLines;
  // Draw the Notes
  for PlayerIndex := 0 to PlayersPlay - 1 do
  begin
    if (Screens > 1) and (GetPlayerScreen(PlayerIndex, PlayersPlay, Screens) <> ScreenAct) then
      Continue;

    GetLaneLayout(PlayerIndex, LaneLeft, LaneRight, LaneWidth, LineTop, LineSpacing);

    TrackIndex := Player[PlayerIndex].Track;
    if CurrentSong.isDuet then
      LyricEngine := ScreenSing.VoiceLyrics[TrackIndex]
    else
      LyricEngine := ScreenSing.Lyrics;
    // Clear the final target notes and sung trace when their lyrics fade out.
    // Each duet voice finishes independently; scoring is unaffected.
    if LyricEngine.GetUpperLine.LastLine and
      not LyricEngine.HasVisibleText(LyricsState.MidBeat) then
    begin
      if Ini.PitchTrace <> 0 then
        SingDrawPlayerLine(LaneLeft, LineTop, LaneWidth, TrackIndex, PlayerIndex, LineSpacing, true);
      Continue;
    end;

    SingDrawPlayerBGLine(LaneLeft, LineTop, LaneRight, TrackIndex, PlayerIndex, LineSpacing);
    SingDrawLine(LaneLeft, LineTop, LaneRight, TrackIndex, PlayerIndex, LineSpacing);
    SingDrawPlayerLine(LaneLeft, LineTop, LaneWidth, TrackIndex, PlayerIndex, LineSpacing);
  end;
end;

// Draw Note Bars for Editor
// There are 11 reasons for a new procedure:   (nice binary :D )
// 1. It does not look good when you draw the golden note star effect in the editor
// 2. You can see the freestyle notes in the editor semitransparent
// 3. It is easier and faster then changing the old procedure
procedure EditDrawBackgroundVoices(X, YBaseNote, W, H: real; SelectedTrack, VoiceCount: integer);
var
  Track, Line, Note, ViewStart, ViewEnd, Base: integer;
  Scale, Left, Right, Top: real;
begin
  with CurrentSong.Tracks[SelectedTrack].Lines[CurrentSong.Tracks[SelectedTrack].CurrentLine] do
  begin
    if not HasLength(Scale) or (Scale <= 0) then Exit;
    Scale := W / Scale;
    ViewStart := Notes[0].StartBeat;
    ViewEnd := EndBeat;
    Base := BaseNote;
  end;
  for Track := 0 to VoiceCount - 1 do
    if Track <> SelectedTrack then
      for Line := 0 to High(CurrentSong.Tracks[Track].Lines) do
        with CurrentSong.Tracks[Track].Lines[Line] do
          if (Length(Notes) > 0) and (Notes[0].StartBeat < ViewEnd) and
            (Notes[HighNote].EndBeat > ViewStart) then
            for Note := 0 to HighNote do
              with Notes[Note] do
              begin
                Left := Max(X, X + (StartBeat - ViewStart) * Scale);
                Right := Min(X + W, X + (EndBeat - ViewStart) * Scale);
                Top := YBaseNote - (Tone - Base) * H / 18 - NotesH[0];
                if (Right > Left) and (Top >= YBaseNote - 7 * H / 9) and
                  (Top + 2 * NotesH[0] <= YBaseNote + 2 * H / 9) then
                  Renderer.DrawQuad(Left, Top, 0, Right - Left, 2 * NotesH[0], Theme.EditSub.InactiveVoiceColor.R,
                    Theme.EditSub.InactiveVoiceColor.G, Theme.EditSub.InactiveVoiceColor.B,
                    Theme.EditSub.InactiveVoiceAlpha);
              end;
end;

procedure EditDrawLine(X, YBaseNote, W, H: real; Track: integer; NumLines: integer);
var
  Rec:   TRecR;
  Count: integer;
  TempR: real;
  GoldenStarPos: real;
  Space: real;
  Texture: TTexture;
  ColorR, ColorG, ColorB, A: single;
begin
  Space := H / (NumLines - 1);

  if not CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].HasLength(TempR) then TempR := 0
  else TempR := W / TempR;

  with CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine] do
  begin
    for Count := 0 to HighNote do
    begin
      with Notes[Count] do
      begin

        // Golden Note Patch
        case NoteType of
          ntFreestyle:
          begin
            ColorR := 1;
            ColorG := 1;
            ColorB := 1;
            A := 0.35;
          end;
          ntNormal:
          begin
            ColorR := 1;
            ColorG := 1;
            ColorB := 1;
            A := 0.85;
          end;
          ntGolden:
          begin
            ColorR := 1;
            ColorG := 1;
            ColorB := 0.3;
            A := 0.85;
          end;
          ntRap:
          begin
            if (Color = P1_INVERTED) then
            begin
              ColorR := 1;
              ColorG := 1;
              ColorB := 1;
              A := 0.75;
            end
            else
            begin
              ColorR := 1;
              ColorG := 1;
              ColorB := 1;
              A := 0.5;
            end;
          end;
          ntRapGolden:
          begin
            if (Color = P1_INVERTED) then
            begin
              ColorR := 1;
              ColorG := 1;
              ColorB := 0.3;
              A := 0.75;
            end
            else
            begin
              ColorR := 1;
              ColorG := 1;
              ColorB := 0.3;
              A := 0.5;
            end;
          end;
        end; // case

        // left part
        Rec.Left  := (StartBeat - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat) * TempR + X + 0.5;
        Rec.Right := Rec.Left + NotesW[0];
        Rec.Top := YBaseNote - (Tone-BaseNote)*Space/2 - NotesH[0];
        Rec.Bottom := Rec.Top + 2 * NotesH[0];
        If IsUnpitchedNote(NoteType) then
        begin
          If Color = P1_INVERTED then
            Texture := Tex_Left_Rap_Inv
          else
            Texture := Tex_Left_Rap[Color];
        end
        else
        begin
          If Color = P1_INVERTED then
            Texture := Tex_Left_Inv
          else
            Texture := Tex_Left[Color];
        end;
        with Texture do
        begin
          X := Rec.Left;
          Y := Rec.Top;
          W := Rec.Right - Rec.Left;
          H := Rec.Bottom - Rec.Top;
          ColR := ColorR;
          ColG := ColorG;
          ColB := ColorB;
          Alpha := A;
          TexX1 := 0;
          TexX2 := 1;
          TexY1 := 0;
          TexY2 := 1;
        end;
        Renderer.DrawTexture(Texture);
        GoldenStarPos := Rec.Left;

        // middle part
        Rec.Left  := Rec.Right;
        Rec.Right := (StartBeat + Duration - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat) * TempR + X - NotesW[0] - 0.5;

        If IsUnpitchedNote(NoteType) then
        begin
          If Color = P1_INVERTED then
            Texture := Tex_Mid_Rap_Inv
          else
            Texture := Tex_Mid_Rap[Color];
        end
        else
        begin
          If Color = P1_INVERTED then
            Texture := Tex_Mid_Inv
          else
            Texture := Tex_Mid[Color];
        end;
        with Texture do
        begin
          X := Rec.Left;
          Y := Rec.Top;
          W := Rec.Right - Rec.Left;
          H := Rec.Bottom - Rec.Top;
          ColR := ColorR;
          ColG := ColorG;
          ColB := ColorB;
          Alpha := A;
          TexX1 := 0;
          TexX2 := 1;
          TexY1 := 0;
          TexY2 := 1;
        end;
        Renderer.DrawTexture(Texture);

        // right part
        Rec.Left  := Rec.Right;
        Rec.Right := Rec.Right + NotesW[0];

        If IsUnpitchedNote(NoteType) then
        begin
          If Color = P1_INVERTED then
            Texture := Tex_Right_Rap_Inv
          else
            Texture := Tex_Right_Rap[Color]
        end
        else
        begin
          If Color = P1_INVERTED then
            Texture := Tex_Right_Inv
          else
            Texture := Tex_Right[Color]
        end;
        with Texture do
        begin
          X := Rec.Left;
          Y := Rec.Top;
          W := Rec.Right - Rec.Left;
          H := Rec.Bottom - Rec.Top;
          ColR := ColorR;
          ColG := ColorG;
          ColB := ColorB;
          Alpha := A;
          TexX1 := 0;
          TexX2 := 1;
          TexY1 := 0;
          TexY2 := 1;
        end;
        Renderer.DrawTexture(Texture);

        if ((NoteType = ntGolden) or (NoteType = ntRapGolden)) and (Ini.EffectSing = 1) then
        begin
          GoldenRec.SaveGoldenStarsRec(GoldenStarPos, Rec.Top, Rec.Right, Rec.Bottom);
        end;
        
      end; // with
    end; // for
  end; // with
end;

procedure EditDrawBorderedBox(X, Y, W, H: integer; FillR, FillG, FillB, FillAlpha: real);
begin
  Renderer.Blend := false;
  Renderer.DrawQuad(X, Y, 0, W, H, FillR, FillG, FillB, FillAlpha);
  Renderer.DrawBoundedBox(X-1, Y-1, X+W+1, Y+H+1, 0, 2, 0, 0, 0, 1);
  Renderer.Blend := true;
end;

procedure EditDrawBeatDelimiters(X, Y, W, H: real; Track: integer);
var
  Count, I: integer;
  TempR: real;
  LineList: TLineList;
begin
  if ((CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].EndBeat < CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat)) then
    Exit;

  if not CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].HasLength(TempR) then TempR := 0
  else TempR := W / TempR;

  if (CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].ScoreValue > 0) and ( W > 0 ) and ((CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].EndBeat > CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat)) then
      TempR := W / (CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].EndBeat - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat)
    else
      TempR := 0;
  SetLength(LineList, CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].EndBeat - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat + 1);
  I := 0;
  for Count := CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat to CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].EndBeat do
  begin
    with LineList[I] do
    begin
      X1 := X + TempR * (Count - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat);
      Y1 := Y;
      X2 := X + TempR * (Count - CurrentSong.Tracks[Track].Lines[CurrentSong.Tracks[Track].CurrentLine].Notes[0].StartBeat);
      Y2 := Y + H;
      Z := 0;
      Thickness := 2;
      ColR := 0;
      ColG := 0;
      ColB := 0;
    end;
    if (Count mod USong.DEFAULT_RESOLUTION) = CurrentSong.Tracks[Track].NotesGAP then
      LineList[I].Alpha := 1
    else
      LineList[I].Alpha := 0.3;
    I := I + 1;
  end;
  Renderer.DrawLines(LineList);
end;


end.
