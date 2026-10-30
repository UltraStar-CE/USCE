{* UltraStar Deluxe - Karaoke Game
 *
 * Typed remote-control command names for browser-based USDX remotes.
 * This unit deliberately models semantic commands instead of OS-level
 * keyboard injection.
 *}

unit URemoteControl;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$H+}

uses
  SysUtils;

type
  TRemoteControlCommand = (
    rccUnknown,
    rccMenuUp,
    rccMenuDown,
    rccMenuLeft,
    rccMenuRight,
    rccMenuSelect,
    rccMenuBack,
    rccGamePause,
    rccGameResume,
    rccSongSkipIntro,
    rccSongRestart,
    rccSongMenu,
    rccSongPlaylistMenu,
    rccSongJumpTo,
    rccSongRandom,
    rccSongSelect,
    rccSongStart,
    rccPreviewStart,
    rccPreviewStop,
    rccSearchSetText,
    rccPlaylistLoad,
    rccPlaylistCreate,
    rccPlaylistDelete,
    rccPlaylistRemoveItem,
    rccPlaylistAddSelected,
    rccPlaylistRemoveSelected,
    rccPlaylistAddSongs,
    rccPlaylistRemoveSong,
    rccPlaylistMoveItemUp,
    rccPlaylistMoveItemDown,
    rccPlaylistToggleFixedOrder,
    rccContinuousStart, rccContinuousQueue, rccContinuousStop, rccContinuousSkip, rccContinuousConfirm
  );

function TryParseRemoteControlCommand(const CommandName: UTF8String;
  out Command: TRemoteControlCommand): boolean;
function RemoteControlCommandToString(Command: TRemoteControlCommand): UTF8String;
function IsMenuRemoteControlCommand(Command: TRemoteControlCommand): boolean;
function IsSongRemoteControlCommand(Command: TRemoteControlCommand): boolean;

function IsValidRemotePlaylistName(const Name: UTF8String): boolean;

implementation

function IsValidRemotePlaylistName(const Name: UTF8String): boolean;
var I: integer; Stem: string;
begin
  Result := false;
  if (Trim(string(Name)) = '') or (Length(Name) > 200) then Exit;
  if Name[Length(Name)] in [' ', '.'] then Exit;
  for I := 1 to Length(Name) do
    if (Ord(Name[I]) < 32) or (Pos(Name[I], '<>:"/\|?*') > 0) then Exit;
  Stem := UpperCase(string(Name));
  I := Pos('.', Stem);
  if I > 0 then Stem := Copy(Stem, 1, I - 1);
  if (Stem = 'CON') or (Stem = 'PRN') or (Stem = 'AUX') or (Stem = 'NUL') then Exit;
  if (Length(Stem) = 4) and ((Copy(Stem, 1, 3) = 'COM') or
    (Copy(Stem, 1, 3) = 'LPT')) and (Stem[4] in ['1'..'9']) then Exit;
  Result := true;
end;

function TryParseRemoteControlCommand(const CommandName: UTF8String;
  out Command: TRemoteControlCommand): boolean;
var
  Name: string;
begin
  Name := LowerCase(string(CommandName));
  Result := true;

  if (Name = 'menu.up') then
    Command := rccMenuUp
  else if (Name = 'menu.down') then
    Command := rccMenuDown
  else if (Name = 'menu.left') then
    Command := rccMenuLeft
  else if (Name = 'menu.right') then
    Command := rccMenuRight
  else if (Name = 'menu.select') then
    Command := rccMenuSelect
  else if (Name = 'menu.back') then
    Command := rccMenuBack
  else if (Name = 'game.pause') then
    Command := rccGamePause
  else if (Name = 'game.resume') then
    Command := rccGameResume
  else if (Name = 'song.skipintro') then
    Command := rccSongSkipIntro
  else if (Name = 'song.restart') then
    Command := rccSongRestart
  else if (Name = 'song.menu') then
    Command := rccSongMenu
  else if (Name = 'song.playlistmenu') then
    Command := rccSongPlaylistMenu
  else if (Name = 'song.jumpto') then
    Command := rccSongJumpTo
  else if (Name = 'song.random') then
    Command := rccSongRandom
  else if (Name = 'song.select') then
    Command := rccSongSelect
  else if (Name = 'song.start') then
    Command := rccSongStart
  else if (Name = 'preview.start') then
    Command := rccPreviewStart
  else if (Name = 'preview.stop') then
    Command := rccPreviewStop
  else if (Name = 'search.settext') then
    Command := rccSearchSetText
  else if (Name = 'playlist.load') then
    Command := rccPlaylistLoad
  else if (Name = 'playlist.create') then
    Command := rccPlaylistCreate
  else if (Name = 'playlist.delete') then
    Command := rccPlaylistDelete
  else if (Name = 'playlist.removeitem') then
    Command := rccPlaylistRemoveItem
  else if (Name = 'playlist.addselected') then
    Command := rccPlaylistAddSelected
  else if (Name = 'playlist.removeselected') then
    Command := rccPlaylistRemoveSelected
  else if (Name = 'playlist.addsongs') then
    Command := rccPlaylistAddSongs
  else if (Name = 'playlist.removesong') then
    Command := rccPlaylistRemoveSong
  else if (Name = 'playlist.moveitemup') then
    Command := rccPlaylistMoveItemUp
  else if (Name = 'playlist.moveitemdown') then
    Command := rccPlaylistMoveItemDown
  else if Name = 'playlist.togglefixedorder' then Command := rccPlaylistToggleFixedOrder
  else if Name = 'continuous.start' then Command := rccContinuousStart
  else if Name = 'continuous.queue' then Command := rccContinuousQueue
  else if Name = 'continuous.stop' then Command := rccContinuousStop
  else if Name = 'continuous.skip' then Command := rccContinuousSkip
  else if Name = 'continuous.confirm' then Command := rccContinuousConfirm
  else
  begin
    Command := rccUnknown;
    Result := false;
  end;
end;

function RemoteControlCommandToString(Command: TRemoteControlCommand): UTF8String;
begin
  case Command of
    rccMenuUp:        Result := 'menu.up';
    rccMenuDown:      Result := 'menu.down';
    rccMenuLeft:      Result := 'menu.left';
    rccMenuRight:     Result := 'menu.right';
    rccMenuSelect:    Result := 'menu.select';
    rccMenuBack:      Result := 'menu.back';
    rccGamePause:     Result := 'game.pause';
    rccGameResume:    Result := 'game.resume';
    rccSongSkipIntro: Result := 'song.skipIntro';
    rccSongRestart:   Result := 'song.restart';
    rccSongMenu:      Result := 'song.menu';
    rccSongPlaylistMenu: Result := 'song.playlistMenu';
    rccSongJumpTo:    Result := 'song.jumpTo';
    rccSongRandom:    Result := 'song.random';
    rccSongSelect:    Result := 'song.select';
    rccSongStart:     Result := 'song.start';
    rccPreviewStart:  Result := 'preview.start';
    rccPreviewStop:   Result := 'preview.stop';
    rccSearchSetText: Result := 'search.setText';
    rccPlaylistLoad:  Result := 'playlist.load';
    rccPlaylistCreate: Result := 'playlist.create';
    rccPlaylistDelete: Result := 'playlist.delete';
    rccPlaylistRemoveItem: Result := 'playlist.removeItem';
    rccPlaylistAddSelected: Result := 'playlist.addSelected';
    rccPlaylistRemoveSelected: Result := 'playlist.removeSelected';
    rccPlaylistAddSongs: Result := 'playlist.addSongs';
    rccPlaylistRemoveSong: Result := 'playlist.removeSong';
    rccPlaylistMoveItemUp: Result := 'playlist.moveItemUp';
    rccPlaylistMoveItemDown: Result := 'playlist.moveItemDown';
    rccPlaylistToggleFixedOrder: Result := 'playlist.toggleFixedOrder';
    rccContinuousStart: Result := 'continuous.start';
    rccContinuousQueue: Result := 'continuous.queue';
    rccContinuousStop: Result := 'continuous.stop';
    rccContinuousSkip: Result := 'continuous.skip';
    rccContinuousConfirm: Result := 'continuous.confirm';
  else
    Result := '';
  end;
end;

function IsMenuRemoteControlCommand(Command: TRemoteControlCommand): boolean;
begin
  Result := Command in [
    rccMenuUp,
    rccMenuDown,
    rccMenuLeft,
    rccMenuRight,
    rccMenuSelect,
    rccMenuBack
  ];
end;

function IsSongRemoteControlCommand(Command: TRemoteControlCommand): boolean;
begin
  Result := Command in [
    rccGamePause,
    rccGameResume,
    rccSongSkipIntro,
    rccSongRestart,
    rccSongMenu,
    rccSongPlaylistMenu,
    rccSongJumpTo,
    rccSongRandom,
    rccSongSelect,
    rccSongStart,
    rccPreviewStart,
    rccPreviewStop,
    rccSearchSetText,
    rccPlaylistLoad,
    rccPlaylistCreate,
    rccPlaylistDelete,
    rccPlaylistRemoveItem,
    rccPlaylistAddSelected,
    rccPlaylistRemoveSelected,
    rccPlaylistAddSongs,
    rccPlaylistRemoveSong,
    rccPlaylistMoveItemUp,
    rccPlaylistMoveItemDown,
    rccPlaylistToggleFixedOrder
  ];
end;

end.
