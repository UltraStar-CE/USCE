unit ULibraryLockdown;

{$mode delphi}

interface

uses Classes, SysUtils;

type
  TLibraryLockdown = class
  private
    FFullLibrary: TList;
    FPassword: UTF8String;
    FActive: boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Activate(LibrarySongs, SelectedSongs: TList; const Password: UTF8String): boolean;
    function CheckPassword(const Password: UTF8String): boolean;
    function Unlock(LibrarySongs: TList; const Password: UTF8String): boolean;
    property Active: boolean read FActive;
  end;

var LibraryLockdown: TLibraryLockdown;

implementation

constructor TLibraryLockdown.Create;
begin
  inherited;
  FFullLibrary := TList.Create;
end;

destructor TLibraryLockdown.Destroy;
begin
  FFullLibrary.Free;
  inherited;
end;

function TLibraryLockdown.Activate(LibrarySongs, SelectedSongs: TList; const Password: UTF8String): boolean;
var I: integer;
begin
  Result := false;
  if FActive or (Password = '') or (SelectedSongs.Count = 0) then Exit;
  FFullLibrary.Assign(LibrarySongs);
  for I := LibrarySongs.Count - 1 downto 0 do
    if SelectedSongs.IndexOf(LibrarySongs[I]) < 0 then LibrarySongs.Delete(I);
  if LibrarySongs.Count = 0 then
  begin
    LibrarySongs.Assign(FFullLibrary);
    FFullLibrary.Clear;
    Exit;
  end;
  FPassword := Password;
  FActive := true;
  Result := true;
end;

function TLibraryLockdown.CheckPassword(const Password: UTF8String): boolean;
begin
  Result := FActive and (Password = FPassword);
end;

function TLibraryLockdown.Unlock(LibrarySongs: TList; const Password: UTF8String): boolean;
begin
  Result := CheckPassword(Password);
  if not Result then Exit;
  LibrarySongs.Assign(FFullLibrary);
  FFullLibrary.Clear;
  FPassword := '';
  FActive := false;
end;

initialization
  LibraryLockdown := TLibraryLockdown.Create;
finalization
  LibraryLockdown.Free;
end.
