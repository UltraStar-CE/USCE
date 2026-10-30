unit UCoverDecode;
{$mode Delphi}
interface
uses Classes, SyncObjs, SDL2, UPath;
type
  TCoverDecode = class(TThread)
  private
    Lock: TCriticalSection;
    Wake: TEvent;
    Pending: array[0..31] of IPath;
    PendingCount, ImageLimit: integer;
    Active, Completed: IPath;
    Surface: PSDL_Surface;
    Generation: cardinal;
    Failed, Wanted: TStringList;
  protected
    procedure Execute; override;
  public
    constructor Create(MaxSize: integer);
    destructor Destroy; override;
    procedure BeginFrame;
    procedure EndFrame;
    procedure Clear;
    function Poll(const Name: IPath; out Image: PSDL_Surface): boolean;
  end;
implementation
uses SysUtils, URenderer;
constructor TCoverDecode.Create(MaxSize: integer);
begin
  inherited Create(true);
  ImageLimit := MaxSize;
  Lock := TCriticalSection.Create;
  Wake := TEvent.Create(nil, false, false, '');
  Failed := TStringList.Create;
  Wanted := TStringList.Create;
  Start;
end;
destructor TCoverDecode.Destroy;
begin
  Terminate;
  Wake.SetEvent;
  WaitFor;
  Clear;
  Wanted.Free;
  Failed.Free;
  Wake.Free;
  Lock.Free;
  inherited;
end;
procedure TCoverDecode.Clear;
var I: integer;
begin
  Lock.Acquire;
  try
    Inc(Generation);
    for I := 0 to PendingCount - 1 do Pending[I] := nil;
    PendingCount := 0;
    Completed := nil;
    SDL_FreeSurface(Surface);
    Surface := nil;
    Failed.Clear;
  finally
    Lock.Release;
  end;
end;
procedure TCoverDecode.BeginFrame;
begin
  Wanted.Clear;
end;
procedure TCoverDecode.EndFrame;
var I, J: integer;
begin
  Lock.Acquire;
  try
    if (Completed <> nil) and (Wanted.IndexOf(Completed.ToUTF8) < 0) then
    begin
      SDL_FreeSurface(Surface);
      Surface := nil;
      Completed := nil;
    end;
    J := 0;
    for I := 0 to PendingCount - 1 do
      if Wanted.IndexOf(Pending[I].ToUTF8) >= 0 then
      begin
        Pending[J] := Pending[I];
        Inc(J);
      end;
    for I := J to PendingCount - 1 do Pending[I] := nil;
    PendingCount := J;
    Wake.SetEvent;
  finally
    Lock.Release;
  end;
end;
function TCoverDecode.Poll(const Name: IPath; out Image: PSDL_Surface): boolean;
var I: integer;
begin
  Image := nil;
  Result := false;
  if (Name = nil) or Name.IsUnset then Exit;
  Wanted.Add(Name.ToUTF8);
  Lock.Acquire;
  try
    if (Completed <> nil) and (Completed.ToUTF8 = Name.ToUTF8) then
    begin
      Image := Surface;
      Surface := nil;
      Completed := nil;
      Wake.SetEvent;
      Exit(true);
    end;
    if Failed.IndexOf(Name.ToUTF8) >= 0 then Exit;
    if (Active <> nil) and (Active.ToUTF8 = Name.ToUTF8) then Exit;
    for I := 0 to PendingCount - 1 do
      if Pending[I].ToUTF8 = Name.ToUTF8 then Exit;
    if PendingCount = Length(Pending) then Exit;
    Pending[PendingCount] := Name;
    Inc(PendingCount);
    Wake.SetEvent;
  finally
    Lock.Release;
  end;
end;
procedure TCoverDecode.Execute;
var Name: IPath; Image: PSDL_Surface; Epoch: cardinal; I: integer;
begin
  while not Terminated do
  begin
    Name := nil;
    Lock.Acquire;
    try
      if (Completed = nil) and (PendingCount > 0) then
      begin
        Name := Pending[0];
        Dec(PendingCount);
        for I := 0 to PendingCount - 1 do Pending[I] := Pending[I+1];
        Pending[PendingCount] := nil;
        Active := Name;
        Epoch := Generation;
      end;
    finally
      Lock.Release;
    end;
    if Name = nil then
    begin
      Wake.WaitFor(100);
      Continue;
    end;
    Image := nil;
    try
      // CPU work only. GPU upload and per-widget styling stay on the UI thread.
      Image := PrepareTextureSurface(Name, TEXTURE_TYPE_PLAIN, 0, ImageLimit);
    except
      SDL_FreeSurface(Image);
      Image := nil;
    end;
    Lock.Acquire;
    try
      Active := nil;
      if (Epoch <> Generation) or Terminated then
        SDL_FreeSurface(Image)
      else if Image = nil then
      begin
        // Bound failed-path bookkeeping too; never retry a broken image each frame.
        if Failed.Count = 256 then Failed.Delete(0);
        Failed.Add(Name.ToUTF8);
      end
      else
      begin
        Completed := Name;
        Surface := Image;
      end;
    finally
      Lock.Release;
    end;
  end;
end;
end.
