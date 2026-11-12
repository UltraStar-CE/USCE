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
 * $URL$
 * $Id$
 *}

unit UMenuBackgroundVideo;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UThemes,
  UMenuBackground,
  UMusic,
  UVideo,
  UTime,
  UPath;

//TMenuBackgroundColor - Background Color
//--------

type
  //DefaultBGVideoPlayback = TVideoPlayback_FFmpeg;

{type
  TBGVideoPool = class;

  PBGVideoPoolItem = ^TBGVideoPoolItem;
  TBGVideoPoolItem = record
    Parent: TBGVideoPool;
    VideoPlayback = IVideoPlayback;
    ReferenceCounter: cardinal; //Number of Creations
  end;

  TBGVideo = class
    private
      myItem: PBGVideoPoolItem;
    public
      constructor Create(Item: PBGVideoPoolItem); override;

      function    GetVideoPlayback: IVideoPlayback;
      procedure   Draw;

      destructor  Destroy;
  end;

  TBGVideoPool = class
    private
      Items: PBGVideoPoolItem;
    public
      constructor Create;

      function    GetBGVideo(filename: IPath): TBGVideo;
      procedure   RemoveItem(
      procedure   FreeAllItems;

      destructor  Destroy;
  end;

type }
  TMenuVideoState = class
    FileName: IPath;
    Video: IVideo;
    Timer: TRelativeTimer;
    Users: integer;
    constructor Create(const AFileName: IPath);
    destructor Destroy; override;
  end;

  TMenuBackgroundVideo = class (TMenuBackground)
    private
      fFilename: IPath;
      fState: TMenuVideoState;
    public
      constructor Create(const ThemedSettings: TThemeBackground); override;
      procedure   OnShow; override;
      procedure   Draw; override;
      procedure   OnFinish; override;
      destructor  Destroy; override;
  end;

{var
  BGVideoPool: TBGVideoPool;  }
const
  SUPPORTED_EXTS_BACKGROUNDVIDEO: array[0..8] of string = ('.avi', '.mov', '.divx', '.mpg', '.mp4', '.mpeg', '.m2v', '.webm', '.gif');

procedure ClearMenuVideoCache(ReleaseTextures: boolean = false);

implementation

uses
  SysUtils,
  USkins,
  UCommon,
  UGraphic,
  URenderer;

var CachedMenuVideo: TMenuVideoState;

constructor TMenuVideoState.Create(const AFileName: IPath);
begin
  inherited Create;
  FileName := AFileName;
  Timer := TRelativeTimer.Create;
  Video := VideoPlayback.Open(FileName);
  if Video <> nil then
  begin
    Video.Loop := true;
    Video.Play;
  end;
end;

destructor TMenuVideoState.Destroy;
begin
  Video := nil;
  Timer.Free;
  inherited;
end;

procedure ClearMenuVideoCache(ReleaseTextures: boolean = false);
var Old: TMenuVideoState;
begin
  Old := CachedMenuVideo;
  CachedMenuVideo := nil;
  if (Old <> nil) and ReleaseTextures then Old.Video := nil;
  if (Old <> nil) and (Old.Users = 0) then Old.Free;
end;

function AcquireMenuVideo(const FileName: IPath): TMenuVideoState;
begin
  if (CachedMenuVideo = nil) or not CachedMenuVideo.FileName.Equals(FileName) then
  begin
    ClearMenuVideoCache;
    CachedMenuVideo := TMenuVideoState.Create(FileName);
  end;
  Result := CachedMenuVideo;
  Inc(Result.Users);
  Result.Timer.Start;
end;

procedure ReleaseMenuVideo(var State: TMenuVideoState);
var Old: TMenuVideoState;
begin
  Old := State;
  State := nil;
  if Old = nil then Exit;
  Dec(Old.Users);
  if Old.Users = 0 then
  begin
    Old.Timer.Pause;
    if Old <> CachedMenuVideo then Old.Free;
  end;
end;

constructor TMenuBackgroundVideo.Create(const ThemedSettings: TThemeBackground);
begin
  inherited;
  if (Length(ThemedSettings.Tex) = 0) then
    raise EMenuBackgroundError.Create('TMenuBackgroundVideo: No video filename present');

  fFileName := Skin.GetTextureFileName(ThemedSettings.Tex);
  if (not fFilename.IsFile) then
    raise EMenuBackgroundError.Create('TMenuBackgroundVideo: Can''t load background video: ' + fFilename.ToNative);
end;

destructor  TMenuBackgroundVideo.Destroy;
begin
  OnFinish;
  inherited;
end;

procedure TMenuBackgroundVideo.OnShow;
begin
  if fState = nil then fState := AcquireMenuVideo(fFileName);
end;

procedure   TMenuBackgroundVideo.OnFinish;
begin
  ReleaseMenuVideo(fState);
end;

procedure TMenuBackgroundVideo.Draw;
begin
  if SuppressDrawing then Exit;
  // clear just once when in dual screen mode
  if (ScreenAct = 1) then
  begin
    Renderer.ClearFrameBuffer(CLEAR_DEPTH);
    // video failure -> draw blank background
    if (fState = nil) or (fState.Video = nil) then
      Renderer.ClearFrameBuffer(CLEAR_COLOR);
  end;

  if (fState <> nil) and (fState.Video <> nil) then
  begin
    fState.Video.GetFrame(fState.Timer.GetTime());
    fState.Video.SetScreen(ScreenAct);
    fState.Video.Draw();
  end;
end;

// Implementation of TBGVideo
//--------
{constructor TBGVideo.Create(Item: PBGVideoPoolItem);
begin
  myItem := PBGVideoPoolItem;
  Inc(myItem.ReferenceCounter);
end;

destructor  TBGVideo.Destroy;
begin
  Dec(myItem.ReferenceCounter);
end;

function    TBGVideo.GetVideoPlayback: IVideoPlayback;
begin

end;

procedure   TBGVideo.Draw;
begin

end;

// Implementation of TBGVideoPool
//--------

constructor TBGVideoPool.Create;
begin

end;

destructor  TBGVideoPool.Destroy;
begin

end;

function    TBGVideoPool.GetBGVideo(filename: IPath): TBGVideo;
begin

end;

procedure   TBGVideoPool.FreeAllItems;
begin

end;  }

end.
