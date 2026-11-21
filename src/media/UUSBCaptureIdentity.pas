// UltraStar Community Edition - Karaoke Game
// SPDX-License-Identifier: GPL-2.0-or-later

unit UUSBCaptureIdentity;
{$MODE Delphi}{$H+}

interface

function USBCaptureIdentity(Card: integer; out Serial, Model, Instance: UTF8String;
  const SysRoot: string = '/sys'): UTF8String;
function USBInstanceAttached(const Instance: UTF8String): boolean;
function USBModelAvailable(const Model: UTF8String; const Claimed: array of UTF8String;
  const SysRoot: string = '/sys'): boolean;

implementation

uses SysUtils;

function CaptureRealPath(Name, Buffer: PChar): PChar; cdecl; external 'c' name 'realpath';

function ReadUSBAttribute(const Path: string): UTF8String;
var
  Handle: THandle;
  Buffer: array[0..255] of AnsiChar;
  Count: integer;
begin
  Result := '';
  Handle := FileOpen(Path, fmOpenRead);
  if Handle = THandle(-1) then Exit;
  try
    Count := FileRead(Handle, Buffer, SizeOf(Buffer));
    if (Count <= 0) or (Count = SizeOf(Buffer)) then Exit;
    SetString(Result, PAnsiChar(@Buffer[0]), Count);
    Result := Trim(Result);
  finally
    FileClose(Handle);
  end;
end;

function CaptureInstance(const Path: string): UTF8String;
var
  Number: UTF8String;
  Buffer: array[0..4095] of AnsiChar;
begin
  Result := '';
  Number := ReadUSBAttribute(Path + '/devnum');
  if (Number <> '') and (CaptureRealPath(PChar(Path), @Buffer[0]) <> nil) then
    Result := string(PAnsiChar(@Buffer[0])) + ':' + Number;
end;

function USBInstanceAttached(const Instance: UTF8String): boolean;
var
  Separator: integer;
begin
  Separator := LastDelimiter(':', Instance);
  Result := (Separator > 0) and (CaptureInstance(Copy(Instance, 1, Separator - 1)) = Instance);
end;

function ReadCaptureSerial(const Path, Vendor, Product: string): UTF8String;
var
  Prefix, Descriptor: UTF8String;
  I: integer;
begin
  Result := ReadUSBAttribute(Path + '/serial');
  if (Result <> '') or (Vendor <> '1415') then Exit;

  // These SingStar adapters put the unit serial in the USB product string.
  if Product = '0000' then Prefix := 'USBMIC Serial# '
  else if Product = '0020' then Prefix := 'Wireless Mic #'
  else Exit;
  Descriptor := ReadUSBAttribute(Path + '/product');
  if (Length(Descriptor) <> Length(Prefix) + 9) or
     (Copy(Descriptor, 1, Length(Prefix)) <> Prefix) then Exit;
  Delete(Descriptor, 1, Length(Prefix));
  for I := 1 to Length(Descriptor) do
    if not (Descriptor[I] in ['0'..'9']) then Exit;
  if Descriptor <> '000000000' then Result := Descriptor;
end;

function USBCaptureIdentity(Card: integer; out Serial, Model, Instance: UTF8String;
  const SysRoot: string): UTF8String;
var
  Buffer: array[0..4095] of AnsiChar;
  Path, Parent, Vendor, Product, Candidate: string;
  Entry: TSearchRec;
  Matches: integer;
begin
  Result := '';
  Serial := '';
  Model := '';
  Instance := '';
  if Card < 0 then Exit;
  Path := SysRoot + '/class/sound/card' + IntToStr(Card) + '/device';
  if CaptureRealPath(PChar(Path), @Buffer[0]) = nil then Exit;
  Path := PAnsiChar(@Buffer[0]);
  while Pos(SysRoot + '/devices/', Path) = 1 do
  begin
    Vendor := ReadUSBAttribute(Path + '/idVendor');
    Product := ReadUSBAttribute(Path + '/idProduct');
    if (Vendor <> '') and (Product <> '') then
    begin
      Model := Vendor + ':' + Product;
      // The kernel device number identifies this attachment, not the port.
      Instance := CaptureInstance(Path);
      // The first USB device is the microphone. Never take a hub's serial.
      Serial := ReadCaptureSerial(Path, Vendor, Product);
      if Serial = '' then Exit;
      // Reject duplicate firmware serials, including twins that are not
      // exposed as PortAudio devices. Never infer uniqueness from card order.
      if FindFirst(SysRoot + '/bus/usb/devices/*', faAnyFile, Entry) <> 0 then
      begin
        Serial := '';
        Exit;
      end;
      Matches := 0;
      try
        repeat
          Candidate := SysRoot + '/bus/usb/devices/' + Entry.Name;
          if (ReadUSBAttribute(Candidate + '/idVendor') = Vendor) and
             (ReadUSBAttribute(Candidate + '/idProduct') = Product) and
             (ReadCaptureSerial(Candidate, Vendor, Product) = Serial) then Inc(Matches);
        until (Matches > 1) or (FindNext(Entry) <> 0);
      finally
        FindClose(Entry);
      end;
      if Matches = 1 then Result := Model + ':' + Serial
      else Serial := '';
      Exit;
    end;
    Parent := ExtractFileDir(Path);
    if Parent = Path then Exit;
    Path := Parent;
  end;
end;

function USBModelAvailable(const Model: UTF8String; const Claimed: array of UTF8String;
  const SysRoot: string): boolean;
var
  Entry: TSearchRec;
  Path: string;
  Attached: UTF8String;
  I: integer;
begin
  if Model = '' then Exit(false);
  // Missing sysfs data must not prevent SDL from trying an available source.
  if FindFirst(SysRoot + '/bus/usb/devices/*', faAnyFile, Entry) <> 0 then Exit(true);
  Result := false;
  try
    repeat
      Path := SysRoot + '/bus/usb/devices/' + Entry.Name;
      if ReadUSBAttribute(Path + '/idVendor') + ':' + ReadUSBAttribute(Path + '/idProduct') <> Model then Continue;
      Attached := CaptureInstance(Path);
      if Attached = '' then Exit(true);
      I := 0;
      while (I < Length(Claimed)) and (Claimed[I] <> Attached) do Inc(I);
      if I = Length(Claimed) then Exit(true);
    until FindNext(Entry) <> 0;
  finally
    FindClose(Entry);
  end;
end;

end.
