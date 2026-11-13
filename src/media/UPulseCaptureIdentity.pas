// UltraStar Community Edition - Karaoke Game
// SPDX-License-Identifier: GPL-2.0-or-later
// PulseAudio query infrastructure adapted from Thallion's USCE #387.

unit UPulseCaptureIdentity;
{$MODE Delphi}{$H+}

interface

function GetPulseCaptureIdentity(const Tag: UTF8String; out Key, Serial: UTF8String): boolean;

implementation

{$IFDEF LINUX}

uses
  SysUtils,
  ctypes,
  dynlibs,
  sdl2;

const
  PULSE_LIB_NAME = 'libpulse.so.0';
  PULSE_TIMEOUT  = 500; // ms we are willing to wait for the server

  PA_CONTEXT_NOAUTOSPAWN = 1;
  PA_CONTEXT_READY       = 4;
  PA_OPERATION_RUNNING   = 0;
  PA_INVALID_INDEX       = $FFFFFFFF;

{$PACKRECORDS C}
type
  // beginning of pa_source_info from pulse/introspect.h
  PPaSourceInfo = ^TPaSourceInfo;
  TPaSourceInfo = record
    name:        PChar;
    index:       cuint32;
    description: PChar;
    sample_spec: record
      format:   cint;
      rate:     cuint32;
      channels: cuint8;
    end;
    channel_map: record
      channels: cuint8;
      map:      array[0..31] of cint;
    end;
    owner_module: cuint32;
    volume: record
      channels: cuint8;
      values:   array[0..31] of cuint32;
    end;
    mute:                 cint;
    monitor_of_sink:      cuint32;
    monitor_of_sink_name: PChar;
    latency:              cuint64;
    driver:               PChar;
    flags:                cint;
    proplist:             pointer;
  end;
{$PACKRECORDS DEFAULT}

  PPaSourceOutputInfo = ^TPaSourceOutputInfo;
  TPaSourceOutputInfo = record
    index: cuint32;
    name: PChar;
    owner_module, client, source: cuint32;
  end;
  TPaSourceOutputCallback = procedure(context: pointer; info: PPaSourceOutputInfo;
                                      eol: cint; userdata: pointer); cdecl;
  TPaSourceInfoCallback = procedure(context: pointer; info: PPaSourceInfo;
                                    eol: cint; userdata: pointer); cdecl;

var
  LibHandle: TLibHandle = NilHandle;
  LibTried:  boolean = false;

  pa_mainloop_new:       function(): pointer; cdecl;
  pa_mainloop_get_api:   function(mainloop: pointer): pointer; cdecl;
  pa_mainloop_iterate:   function(mainloop: pointer; block: cint; retval: pcint): cint; cdecl;
  pa_mainloop_free:      procedure(mainloop: pointer); cdecl;
  pa_context_new:        function(api: pointer; name: PChar): pointer; cdecl;
  pa_context_connect:    function(context: pointer; server: PChar; flags: cint; spawnApi: pointer): cint; cdecl;
  pa_context_get_state:  function(context: pointer): cint; cdecl;
  pa_context_disconnect: procedure(context: pointer); cdecl;
  pa_context_unref:      procedure(context: pointer); cdecl;
  pa_context_get_source_info_list: function(context: pointer; cb: TPaSourceInfoCallback; userdata: pointer): pointer; cdecl;
  pa_context_get_source_output_info_list: function(context: pointer; cb: TPaSourceOutputCallback; userdata: pointer): pointer; cdecl;
  pa_operation_get_state: function(operation: pointer): cint; cdecl;
  pa_operation_unref:    procedure(operation: pointer); cdecl;
  pa_proplist_gets:      function(proplist: pointer; key: PChar): PChar; cdecl;

function LoadPulse(): boolean;

  function Get(const name: string): pointer;
  begin
    Result := GetProcedureAddress(LibHandle, name);
    if Result = nil then
      LoadPulse := false;
  end;

begin
  if LibTried then
  begin
    Result := (LibHandle <> NilHandle);
    Exit;
  end;
  LibTried := true;
  Result := false;

  LibHandle := LoadLibrary(PULSE_LIB_NAME);
  if LibHandle = NilHandle then
    Exit;

  Result := true;
  @pa_mainloop_new       := Get('pa_mainloop_new');
  @pa_mainloop_get_api   := Get('pa_mainloop_get_api');
  @pa_mainloop_iterate   := Get('pa_mainloop_iterate');
  @pa_mainloop_free      := Get('pa_mainloop_free');
  @pa_context_new        := Get('pa_context_new');
  @pa_context_connect    := Get('pa_context_connect');
  @pa_context_get_state  := Get('pa_context_get_state');
  @pa_context_disconnect := Get('pa_context_disconnect');
  @pa_context_unref      := Get('pa_context_unref');
  @pa_context_get_source_info_list := Get('pa_context_get_source_info_list');
  @pa_context_get_source_output_info_list := Get('pa_context_get_source_output_info_list');
  @pa_operation_get_state := Get('pa_operation_get_state');
  @pa_operation_unref    := Get('pa_operation_unref');
  @pa_proplist_gets      := Get('pa_proplist_gets');

  if not Result then
  begin
    UnloadLibrary(LibHandle);
    LibHandle := NilHandle;
  end;
end;

type
  PIdentityQuery = ^TIdentityQuery;
  TIdentityQuery = record
    Tag: UTF8String;
    Source: cuint32;
    Streams, SerialMatches: integer;
    Key, Serial: UTF8String;
    Keys: array of UTF8String;
    StreamsDone, SourcesDone: boolean;
  end;

procedure StreamInfo(context: pointer; info: PPaSourceOutputInfo; eol: cint;
                     userdata: pointer); cdecl;
var Q: PIdentityQuery;
begin
  Q := PIdentityQuery(userdata);
  if eol <> 0 then
  begin
    Q^.StreamsDone := eol > 0;
    Exit;
  end;
  if (info <> nil) and (info^.name <> nil) and (UTF8String(info^.name) = Q^.Tag) then
  begin
    Inc(Q^.Streams);
    Q^.Source := info^.source;
  end;
end;

procedure SourceInfo(context: pointer; info: PPaSourceInfo; eol: cint;
                     userdata: pointer); cdecl;
var
  Q: PIdentityQuery;
  Bus, Serial, Vendor, Product: PChar;
  Key: UTF8String;
begin
  Q := PIdentityQuery(userdata);
  if eol <> 0 then
  begin
    Q^.SourcesDone := eol > 0;
    Exit;
  end;
  if (info = nil) or (info^.proplist = nil) or
     (info^.monitor_of_sink <> PA_INVALID_INDEX) then Exit;
  Bus := pa_proplist_gets(info^.proplist, 'device.bus');
  if (Bus = nil) or (UTF8String(Bus) <> 'usb') then Exit;
  Serial := pa_proplist_gets(info^.proplist, 'device.serial');
  Vendor := pa_proplist_gets(info^.proplist, 'device.vendor.id');
  Product := pa_proplist_gets(info^.proplist, 'device.product.id');
  if (Serial = nil) or (Serial^ = #0) or (Vendor = nil) or (Vendor^ = #0) or
     (Product = nil) or (Product^ = #0) then Exit;
  Key := UTF8String(Vendor) + ':' + UTF8String(Product) + ':' + UTF8String(Serial);
  SetLength(Q^.Keys, Length(Q^.Keys) + 1);
  Q^.Keys[High(Q^.Keys)] := Key;
  if info^.index = Q^.Source then
  begin
    Q^.Key := Key;
    Q^.Serial := Serial;
  end;
end;

function GetPulseCaptureIdentity(const Tag: UTF8String; out Key, Serial: UTF8String): boolean;
var
  Mainloop, Context: pointer;
  Deadline: QWord;
  State: cint;
  Q: TIdentityQuery;
  K: UTF8String;

  procedure WaitFor(Operation: pointer);
  begin
    if Operation = nil then Exit;
    while (pa_operation_get_state(Operation) = PA_OPERATION_RUNNING) and
          (GetTickCount64 < Deadline) do
    begin
      if pa_mainloop_iterate(Mainloop, 0, nil) = 0 then SDL_Delay(1);
    end;
    pa_operation_unref(Operation);
  end;

begin
  Result := false;
  Key := '';
  Serial := '';
  if not LoadPulse then Exit;
  Mainloop := pa_mainloop_new();
  if Mainloop = nil then Exit;
  try
    Context := pa_context_new(pa_mainloop_get_api(Mainloop), 'USCE capture identity');
    if Context = nil then Exit;
    try
      Deadline := GetTickCount64 + PULSE_TIMEOUT;
      if pa_context_connect(Context, nil, PA_CONTEXT_NOAUTOSPAWN, nil) < 0 then Exit;
      repeat
        if pa_mainloop_iterate(Mainloop, 0, nil) < 0 then Exit;
        State := pa_context_get_state(Context);
        if State < PA_CONTEXT_READY then SDL_Delay(1);
      until (State >= PA_CONTEXT_READY) or (GetTickCount64 >= Deadline);
      if State <> PA_CONTEXT_READY then Exit;

      Q := Default(TIdentityQuery);
      Q.Tag := Tag;
      WaitFor(pa_context_get_source_output_info_list(Context, @StreamInfo, @Q));
      if not Q.StreamsDone or (Q.Streams <> 1) then Exit;
      WaitFor(pa_context_get_source_info_list(Context, @SourceInfo, @Q));
      if not Q.SourcesDone or (Q.Key = '') then Exit;
      for K in Q.Keys do
        if K = Q.Key then Inc(Q.SerialMatches);
      if Q.SerialMatches <> 1 then Exit;
      Key := Q.Key;
      Serial := Q.Serial;
      Result := true;
    finally
      pa_context_disconnect(Context);
      pa_context_unref(Context);
    end;
  finally
    pa_mainloop_free(Mainloop);
  end;
end;

finalization
  if LibHandle <> NilHandle then UnloadLibrary(LibHandle);

{$ELSE}

function GetPulseCaptureIdentity(const Tag: UTF8String; out Key, Serial: UTF8String): boolean;
begin
  Key := '';
  Serial := '';
  Result := false;
end;

{$ENDIF}

end.

