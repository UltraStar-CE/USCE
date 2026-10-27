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

unit ULuaMusic;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses ULua;
function ULuaMusic_OpenSound(L: Plua_State): Integer; cdecl;
function ULuaMusic_PlaySound(L: Plua_State): Integer; cdecl;
function ULuaMusic_UnloadSound(L: Plua_State): Integer; cdecl;
procedure LuaMusicReleasePlugin(Owner: integer);
procedure LuaMusicReleaseAll;
const
  ULuaMusic_Lib_f: array[0..3] of luaL_reg = (
    (name:'OpenSound';func:ULuaMusic_OpenSound),
    (name:'LoadSound';func:ULuaMusic_OpenSound),
    (name:'PlaySound';func:ULuaMusic_PlaySound),
    (name:'UnloadSound';func:ULuaMusic_UnloadSound)
  );
implementation
uses SysUtils, Math, UMusic, UIni, UPath, UPathUtils, ULuaUtils;
type TPluginSound = record
  Owner, Handle: integer;
  Stream: TAudioPlaybackStream;
end;
var Sounds: array of TPluginSound;NextHandle: integer = 1;
procedure ReleaseSound(Index: integer);
begin
  if Sounds[Index].Stream = nil then Exit;
  Sounds[Index].Stream.Stop;
  FreeAndNil(Sounds[Index].Stream);
  Sounds[Index].Owner := -1;
end;
procedure LuaMusicReleasePlugin(Owner: integer);
var I: integer;
begin
  for I := 0 to High(Sounds) do if Sounds[I].Owner = Owner then ReleaseSound(I);
end;
procedure LuaMusicReleaseAll;
var I: integer;
begin
  for I := 0 to High(Sounds) do ReleaseSound(I);
  SetLength(Sounds,0);
end;
function OwnedSound(L: Plua_State): integer;
var I,Owner: integer;Handle: lua_Integer;
begin
  Result := -1;
  if not lua_IsInteger(L,1) then begin luaL_argerror(L,1,'Sound ID expected');Exit;end;
  Handle := lua_tointeger(L,1);Owner := Lua_GetOwner(L).Id;
  for I := 0 to High(Sounds) do
    if (Sounds[I].Handle=Handle) and (Sounds[I].Owner=Owner) and (Sounds[I].Stream<>nil) then Exit(I);
  luaL_argerror(L,1,'Sound ID is unloaded or belongs to another plugin');
end;
function ULuaMusic_OpenSound(L: Plua_State): Integer; cdecl;
var FilePath: IPath;Name: UTF8String;Owner,I: integer;Stream: TAudioPlaybackStream;
begin
  Result := 0;
  if not lua_IsString(L,1) then begin luaL_argerror(L,1,'UTF-8 filename expected');Exit;end;
  Owner := Lua_GetOwner(L).Id;
  if (AudioPlayback=nil) or (NextHandle=High(integer)) then begin luaL_error(L,'Sound playback unavailable');Exit;end;
  Name := lua_toString(L,1);
  if (Pos('/',Name)=0) and (Pos('\',Name)=0) then FilePath := ResolveSoundAsset(Name)
  else FilePath := Path(Name);
  Stream := AudioPlayback.OpenSound(FilePath);
  FilePath := nil;Name := '';
  if Stream=nil then begin luaL_error(L,'Unable to open sound file');Exit;end;
  I := 0;while (I<Length(Sounds)) and (Sounds[I].Stream<>nil) do Inc(I);
  if I=Length(Sounds) then SetLength(Sounds,I+1);
  Sounds[I].Owner := Owner;Sounds[I].Handle := NextHandle;Sounds[I].Stream := Stream;
  Inc(NextHandle);
  Stream.Volume := EnsureRange(Ini.SfxVolume,0,100)/100;
  lua_pushinteger(L,Sounds[I].Handle);Result := 1;
end;
function ULuaMusic_PlaySound(L: Plua_State): Integer; cdecl;
var I:integer;
begin
  Result := 0;I := OwnedSound(L);
  if I<0 then Exit;
  Sounds[I].Stream.Volume := EnsureRange(Ini.SfxVolume,0,100)/100;
  AudioPlayback.PlaySound(Sounds[I].Stream);
end;
function ULuaMusic_UnloadSound(L: Plua_State): Integer; cdecl;
var I:integer;
begin
  Result := 0;I := OwnedSound(L);if I>=0 then ReleaseSound(I);
end;
end.
