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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/base/UCommandLine.pas $
 * $Id: UCommandLine.pas 1939 2009-11-09 00:27:55Z s_alexander $
 *}

unit UCommandLine;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UPath;

type
  TScreenMode = (scmDefault, scmFullscreen, scmWindowed);
  TSplitMode = (spmDefault, spmNoSplit, spmSplit);

  {**
   * Reads infos from ParamStr and set some easy interface variables
   *}
  TCMDParams = class
    private
      fLanguage:   string;
      fResolution: string;

      procedure ShowHelp();

      procedure ReadParamInfo;
      procedure ResetVariables;

      function GetLanguage:   integer;
      function GetResolution: integer;
    public
      // some boolean variables set when reading infos
      Debug:      boolean;
      Benchmark:  boolean;
      NoLog:      boolean;
      CheckSongs: boolean;
      ScreenMode: TScreenMode;
      Joypad:     boolean;
      Split:      TSplitMode;

      // some value variables set when reading infos {-1: Not Set, others: Value}
      Depth:      integer;
      Screens:    integer;

      // some strings set when reading infos {Length=0: Not Set}
      SongPath:   IPath;
      ConfigFile: IPath;
      ScoreFile:  IPath;
      Song:       IPath;

      Renderer: string;
      Lockdown: boolean;
      PlaylistNames: array of UTF8String;
      LockdownPassword, StartupError: UTF8String;

      // pseudo integer values
      property Language:      integer read GetLanguage;
      property Resolution:    integer read GetResolution;

      property CustomResolution:    string read fResolution;

      // some procedures for reading infos
      constructor Create;
  end;

var
  Params:    TCMDParams;

const
  cHelp            = 'help';
  cDebug           = 'debug';
  cCheckSongs      = 'check-songs';
  cMediaInterfaces = 'showinterfaces';
  cSong            = 'song';


implementation

uses SysUtils,
     UPlatform;

{**
 * Resets variables and reads info
 *}
constructor TCMDParams.Create;
begin
  inherited;
  
  if FindCmdLineSwitch( cHelp ) or FindCmdLineSwitch( 'h' ) then
    ShowHelp();

  ResetVariables;
  ReadParamInfo;
end;

procedure TCMDParams.ShowHelp();

  function Fmt(aString : string) : string;
  begin
    Result := Format('%-15s', [aString]);
  end;

begin
  writeln;
  writeln('**************************************************************');
  writeln('  UltraStar Community Edition - Command line switches                    ');
  writeln('**************************************************************');
  writeln;
  writeln('  '+ Fmt('Switch') +' : Purpose');
  writeln('  ----------------------------------------------------------');
  writeln('  '+ Fmt(cMediaInterfaces) +' : Show in-use media interfaces');
  writeln('  '+ Fmt(cDebug) +' : Display Debugging info');
  writeln('  '+ Fmt(cCheckSongs) +' : Fully validate song files during startup');
  writeln('  '+ Fmt(cSong + ' <file>') +' : Sing only the given song file, then exit');
  writeln('  -lockdown -playlist <name[,name]> -password <password>');
  writeln('    Start locked playback; -playlist can be repeated.');
  writeln;

  platform.halt;
end;

{**
 * Reset Class Variables
 *}
procedure TCMDParams.ResetVariables;
begin
  Lockdown := false;
  PlaylistNames := nil;
  LockdownPassword := '';
  StartupError := '';
  Debug       := false;
  Benchmark   := False;
  NoLog       := false;
  CheckSongs  := false;
  ScreenMode  := scmDefault;
  Joypad      := False;
  Split       := spmDefault;

  // some value variables set when reading infos {-1: Not Set, others: Value}
  fResolution := '';
  fLanguage   := '';
  Depth       := -1;
  Screens     := -1;

  // some strings set when reading infos {Length=0 Not Set}
  SongPath    := PATH_NONE;
  ConfigFile  := PATH_NONE;
  ScoreFile   := PATH_NONE;
  Song        := PATH_NONE;
end;

{**
 * Read command-line parameters
 *}
procedure TCMDParams.ReadParamInfo;
var
  I:        integer;
  PCount:   integer;
  Command:  string;
  SkipThrough, Start, J: integer;
  Value, Name: UTF8String;
begin
  SkipThrough := 0;
  PCount := ParamCount;
  //Log.LogError('ParamCount: ' + Inttostr(PCount));

  // check all parameters
  for I := 1 to PCount do
  begin
    if I <= SkipThrough then Continue;
    Command := ParamStr(I);
    // check if the string is a parameter
    if (Length(Command) > 1) and (Command[1] = '-') then
    begin
      // remove '-' from command
      Command := LowerCase(Trim(Copy(Command, 2, Length(Command) - 1)));
      //Log.LogError('Command prepared: ' + Command);

      // check command

      // boolean triggers
      if Command = 'lockdown' then
        Lockdown := true
      else if (Command = 'playlist') or (Command = 'password') then
      begin
        if (I = PCount) or (ParamStr(I + 1) = '') or (ParamStr(I + 1)[1] = '-') then
        begin
          StartupError := 'Missing value for -' + Command;
          Continue;
        end;
        SkipThrough := I + 1;
        Value := UTF8Encode(UnicodeString(ParamStr(I + 1)));
        if Command = 'password' then LockdownPassword := Value
        else
        begin
          Start := 1;
          for J := 1 to Length(Value) + 1 do
            if (J > Length(Value)) or (Value[J] = ',') then
            begin
              Name := Trim(Copy(Value, Start, J - Start));
              if Name = '' then StartupError := 'Empty playlist name'
              else begin
                SetLength(PlaylistNames, Length(PlaylistNames) + 1);
                PlaylistNames[High(PlaylistNames)] := Name;
              end;
              Start := J + 1;
            end;
        end;
      end
      else if (Command = 'debug') then
        Debug       := True
      else if (Command = cCheckSongs) then
        CheckSongs  := True
      else if (Command = 'benchmark') then
        Benchmark   := True
      else if (Command = 'nolog') then
        NoLog       := True
      else if (Command = 'fullscreen') then
        ScreenMode  := scmFullscreen
      else if (Command = 'window') then
        ScreenMode  := scmWindowed
      else if (Command = 'joypad') then
        Joypad    := True
      else if (Command = 'split') then
        Split     := spmSplit
      else if (Command = 'nosplit') then
        Split     := spmNoSplit

      // integer variables
      else if (Command = 'depth') then
      begin
        // check if there is another Parameter to get the Value from
        if (PCount > I) then
        begin
          Command := ParamStr(I + 1);

          // check for valid value
          // FIXME: guessing an array-index of depth is very error prone.
          If (Command = '16') then
            Depth := 0
          Else If (Command = '32') then
            Depth := 1;
        end;
      end

      else if (Command = 'screens') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          Command := ParamStr(I + 1);

          // check for valid value
          If (Command = '1') then
            Screens := 0
          Else If (Command = '2') then
            Screens := 1;
        end;
      end

      // pseudo integer values
      else if (Command = 'language') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          fLanguage := Lowercase(ParamStr(I + 1));
        end;
      end

      else if (Command = 'resolution') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          fResolution := Lowercase(ParamStr(I + 1));
        end;
      end

      // string values
      else if (Command = 'songpath') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          SongPath := Path(ParamStr(I + 1));
        end;
      end

      else if (Command = 'configfile') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          ConfigFile := Path(ParamStr(I + 1));

          // is this a relative path -> then add gamepath
          if (not ConfigFile.IsAbsolute) then
            ConfigFile := Platform.GetExecutionDir().Append(ConfigFile);
        end;
      end

      else if (Command = 'scorefile') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          ScoreFile := Path(ParamStr(I + 1));
        end;
      end

      else if (Command = cSong) then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          Song := Path(ParamStr(I + 1)).GetAbsolutePath;
        end;
      end

      else if (Command = 'renderer') then
      begin
        // check if there is another parameter to get the value from
        if (PCount > I) then
        begin
          // write value to string
          Renderer := (ParamStr(I + 1));
        end;
      end;

    end;

  end;

{
  Log.LogInfo('Screens: ' + Inttostr(Screens));
  Log.LogInfo('Depth: ' + Inttostr(Depth));

  Log.LogInfo('Resolution: ' + Inttostr(Resolution));
  Log.LogInfo('Language: ' + Inttostr(Language));

  Log.LogInfo('sResolution: ' + sResolution);
  Log.LogInfo('sLanguage: ' + sLanguage);

  Log.LogInfo('ConfigFile: ' + ConfigFile);
  Log.LogInfo('SongPath: ' + SongPath);
  Log.LogInfo('ScoreFile: ' + ScoreFile);
}

  if Lockdown then
  begin
    if LockdownPassword = '' then StartupError := '-lockdown requires -password';
    if Length(PlaylistNames) = 0 then StartupError := '-lockdown requires -playlist';
    if Song.IsSet then StartupError := '-lockdown cannot be combined with -song';
  end
  else if (Length(PlaylistNames) > 0) or (LockdownPassword <> '') then
    StartupError := '-playlist and -password require -lockdown';

end;

//-------------
// GetLanguage - Get Language ID from saved String Information
//-------------
function TCMDParams.GetLanguage: integer;
begin
  Result := StrToIntDef(fLanguage, -1);
end;

//-------------
// GetResolution - Get Resolution ID from saved String Information
//-------------
function TCMDParams.GetResolution: integer;
begin
  Result := StrToIntDef(fResolution, -1);
end;

end.
