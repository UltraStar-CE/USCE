{ Minimal bindings for the libmpv client and OpenGL render APIs.
  See https://github.com/mpv-player/mpv/tree/v0.41.0/include/mpv

  Copyright (C) 2017-2018 the mpv developers

  Permission to use, copy, modify, and/or distribute this software for any
  purpose with or without fee is hereby granted, provided that the above
  copyright notice and this permission notice appear in all copies.

  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. }
unit mpv;

{$IFDEF FPC}
  {$MODE Delphi}
  {$H+}
  {$PACKRECORDS C}
{$ENDIF}

interface

uses
  ctypes;

const
  MPV_FORMAT_NONE = 0;
  MPV_FORMAT_STRING = 1;
  MPV_FORMAT_FLAG = 3;
  MPV_FORMAT_INT64 = 4;
  MPV_FORMAT_DOUBLE = 5;

  MPV_EVENT_NONE = 0;
  MPV_EVENT_SHUTDOWN = 1;
  MPV_EVENT_LOG_MESSAGE = 2;
  MPV_EVENT_GET_PROPERTY_REPLY = 3;
  MPV_EVENT_SET_PROPERTY_REPLY = 4;
  MPV_EVENT_COMMAND_REPLY = 5;
  MPV_EVENT_END_FILE = 7;
  MPV_EVENT_FILE_LOADED = 8;
  MPV_EVENT_VIDEO_RECONFIG = 17;
  MPV_EVENT_SEEK = 20;
  MPV_EVENT_PLAYBACK_RESTART = 21;
  MPV_EVENT_PROPERTY_CHANGE = 22;
  MPV_EVENT_QUEUE_OVERFLOW = 24;

  MPV_END_FILE_REASON_ERROR = 4;

  MPV_RENDER_PARAM_INVALID = 0;
  MPV_RENDER_PARAM_API_TYPE = 1;
  MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2;
  MPV_RENDER_PARAM_OPENGL_FBO = 3;
  MPV_RENDER_PARAM_FLIP_Y = 4;
  MPV_RENDER_PARAM_X11_DISPLAY = 8;
  MPV_RENDER_PARAM_WL_DISPLAY = 9;
  MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 12;
  MPV_RENDER_UPDATE_FRAME = 1;

type
  Pmpv_handle = Pointer;
  Pmpv_render_context = Pointer;
  PPAnsiChar = ^PAnsiChar;

  Tmpv_event = record
    event_id: cint;
    error: cint;
    reply_userdata: cuint64;
    data: Pointer;
  end;
  Pmpv_event = ^Tmpv_event;

  Tmpv_event_property = record
    name: PAnsiChar;
    format: cint;
    data: Pointer;
  end;
  Pmpv_event_property = ^Tmpv_event_property;

  Tmpv_event_end_file = record
    reason: cint;
    error: cint;
    playlist_entry_id: cint64;
    playlist_insert_id: cint64;
    playlist_insert_num_entries: cint;
  end;
  Pmpv_event_end_file = ^Tmpv_event_end_file;

  Tmpv_event_log_message = record
    prefix: PAnsiChar;
    level: PAnsiChar;
    text: PAnsiChar;
    log_level: cint;
  end;
  Pmpv_event_log_message = ^Tmpv_event_log_message;

  Tmpv_render_param = record
    param_type: cint;
    data: Pointer;
  end;
  Pmpv_render_param = ^Tmpv_render_param;

  Tmpv_get_proc_address = function(Context: Pointer; Name: PAnsiChar): Pointer; cdecl;
  Tmpv_render_update_fn = procedure(Context: Pointer); cdecl;

  Tmpv_opengl_init_params = record
    get_proc_address: Tmpv_get_proc_address;
    get_proc_address_ctx: Pointer;
    { ABI 1 had this deprecated trailing member. Keep it nil; ABI 2 ignores it. }
    extra_exts: PAnsiChar;
  end;

  Tmpv_opengl_fbo = record
    fbo: cint;
    w, h: cint;
    internal_format: cint;
  end;

var
  mpv_client_api_version: function(): culong; cdecl;
  mpv_error_string: function(ErrorCode: cint): PAnsiChar; cdecl;
  mpv_create: function(): Pmpv_handle; cdecl;
  mpv_initialize: function(Handle: Pmpv_handle): cint; cdecl;
  mpv_terminate_destroy: procedure(Handle: Pmpv_handle); cdecl;
  mpv_set_option_string: function(Handle: Pmpv_handle; Name, Value: PAnsiChar): cint; cdecl;
  mpv_command_async: function(Handle: Pmpv_handle; ReplyUserdata: cuint64; Args: PPAnsiChar): cint; cdecl;
  mpv_set_property_async: function(Handle: Pmpv_handle; ReplyUserdata: cuint64; Name: PAnsiChar; Format: cint; Data: Pointer): cint; cdecl;
  mpv_get_property_async: function(Handle: Pmpv_handle; ReplyUserdata: cuint64; Name: PAnsiChar; Format: cint): cint; cdecl;
  mpv_observe_property: function(Handle: Pmpv_handle; ReplyUserdata: cuint64; Name: PAnsiChar; Format: cint): cint; cdecl;
  mpv_request_log_messages: function(Handle: Pmpv_handle; Level: PAnsiChar): cint; cdecl;
  mpv_wait_event: function(Handle: Pmpv_handle; Timeout: cdouble): Pmpv_event; cdecl;
  mpv_render_context_create: function(out Context: Pmpv_render_context; Handle: Pmpv_handle; Params: Pmpv_render_param): cint; cdecl;
  mpv_render_context_set_update_callback: procedure(Context: Pmpv_render_context; Callback: Tmpv_render_update_fn; CallbackContext: Pointer); cdecl;
  mpv_render_context_update: function(Context: Pmpv_render_context): cuint64; cdecl;
  mpv_render_context_render: function(Context: Pmpv_render_context; Params: Pmpv_render_param): cint; cdecl;
  mpv_render_context_free: procedure(Context: Pmpv_render_context); cdecl;

{ Each successful load must be paired with a release. Active videos retain
  their own reference so provider shutdown cannot unload their functions. }
function LoadMpv(): boolean;
procedure UnloadMpv();
function MpvLoadError(): string;

implementation

uses
  SysUtils,
  Dynlibs;

var
  libraryHandle: TLibHandle = NilHandle;
  references: integer = 0;
  loadError: string = '';

function LoadSymbol(const Name: AnsiString; var Address): boolean;
begin
  Pointer(Address) := GetProcedureAddress(libraryHandle, PAnsiChar(Name));
  Result := Pointer(Address) <> nil;
  if not Result then
    loadError := 'Missing libmpv function ' + Name;
end;

function LoadMpv(): boolean;
const
{$IFDEF MSWINDOWS}
  libraryNames: array[0..1] of string = ('libmpv-2.dll', 'mpv-2.dll');
{$ELSE}
  {$IFDEF DARWIN}
  libraryNames: array[0..2] of string = ('libmpv.2.dylib', 'libmpv.1.dylib', 'libmpv.dylib');
  {$ELSE}
  libraryNames: array[0..2] of string = ('libmpv.so.2', 'libmpv.so.1', 'libmpv.so');
  {$ENDIF}
{$ENDIF}
var
  i: integer;
  version: culong;
begin
  if references > 0 then
  begin
    Inc(references);
    Exit(true);
  end;

  Result := false;
  loadError := 'libmpv could not be loaded';
  for i := Low(libraryNames) to High(libraryNames) do
  begin
    libraryHandle := LoadLibrary(libraryNames[i]);
    if libraryHandle <> NilHandle then
      Break;
  end;
  if libraryHandle = NilHandle then
    Exit;

  Result :=
    LoadSymbol('mpv_client_api_version', mpv_client_api_version) and
    LoadSymbol('mpv_error_string', mpv_error_string) and
    LoadSymbol('mpv_create', mpv_create) and
    LoadSymbol('mpv_initialize', mpv_initialize) and
    LoadSymbol('mpv_terminate_destroy', mpv_terminate_destroy) and
    LoadSymbol('mpv_set_option_string', mpv_set_option_string) and
    LoadSymbol('mpv_command_async', mpv_command_async) and
    LoadSymbol('mpv_set_property_async', mpv_set_property_async) and
    LoadSymbol('mpv_get_property_async', mpv_get_property_async) and
    LoadSymbol('mpv_observe_property', mpv_observe_property) and
    LoadSymbol('mpv_request_log_messages', mpv_request_log_messages) and
    LoadSymbol('mpv_wait_event', mpv_wait_event) and
    LoadSymbol('mpv_render_context_create', mpv_render_context_create) and
    LoadSymbol('mpv_render_context_set_update_callback', mpv_render_context_set_update_callback) and
    LoadSymbol('mpv_render_context_update', mpv_render_context_update) and
    LoadSymbol('mpv_render_context_render', mpv_render_context_render) and
    LoadSymbol('mpv_render_context_free', mpv_render_context_free);
  if Result then
  begin
    version := mpv_client_api_version();
    { Keep the minimum in sync with the mpv check in configure.ac. }
    Result := ((version shr 16 = 1) and ((version and $FFFF) >= 107)) or
              (version shr 16 = 2);
    if not Result then
      loadError := 'Unsupported libmpv client API version ' + IntToStr(version);
  end;

  if Result then
  begin
    references := 1;
    loadError := '';
  end
  else
  begin
    UnloadLibrary(libraryHandle);
    libraryHandle := NilHandle;
  end;
end;

procedure UnloadMpv();
begin
  if references = 0 then
    Exit;
  Dec(references);
  if references = 0 then
  begin
    UnloadLibrary(libraryHandle);
    libraryHandle := NilHandle;
  end;
end;

function MpvLoadError(): string;
begin
  Result := loadError;
end;

end.
