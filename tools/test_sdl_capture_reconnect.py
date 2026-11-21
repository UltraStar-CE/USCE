"""Exercise Linux USB identity and reconnect candidates using a synthetic sysfs tree."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

PROBE = """program capture_identity_probe;
{$MODE Delphi}{$H+}
uses SysUtils, UUSBCaptureIdentity;
var
  Serial, Model, Instance, Key: UTF8String;
  Claimed: array of UTF8String;
  I: integer;
begin
  if ParamStr(1) = 'identify' then
  begin
    Key := USBCaptureIdentity(StrToInt(ParamStr(3)), Serial, Model, Instance, ParamStr(2));
    WriteLn(Key);
    WriteLn(Serial);
    WriteLn(Model);
    WriteLn(Instance);
  end
  else if ParamStr(1) = 'attached' then
    WriteLn(Ord(USBInstanceAttached(ParamStr(3))))
  else
  begin
    SetLength(Claimed, ParamCount - 3);
    for I := 0 to High(Claimed) do Claimed[I] := ParamStr(I + 4);
    WriteLn(Ord(USBModelAvailable(ParamStr(3), Claimed, ParamStr(2))));
  end;
end.
"""


def add_usb(root, card, product, descriptor, address, vendor="1415"):
    name = f"1-{card + 1}"
    device = root / "devices" / "usb1" / name
    interface = device / f"{name}:1.0"
    interface.mkdir(parents=True)
    for key, value in {"idVendor": vendor, "idProduct": product,
                       "product": descriptor, "devnum": str(address)}.items():
        (device / key).write_text(value + "\n", encoding="ascii")
    sound_card = root / "class" / "sound" / f"card{card}"
    sound_card.mkdir(parents=True)
    (sound_card / "device").symlink_to(interface)
    (root / "bus" / "usb" / "devices" / name).symlink_to(device)
    return device


def main():
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        root = work / "sys"
        (root / "bus" / "usb" / "devices").mkdir(parents=True)
        source = work / "capture_identity_probe.pas"
        source.write_text(PROBE, encoding="ascii")
        subprocess.run(
            ["fpc", f"-Fu{ROOT / 'src' / 'media'}", f"-FU{work}", str(source)],
            cwd=work, check=True, stdout=subprocess.PIPE,
        )
        executable = work / source.stem

        def probe(mode, *args):
            return subprocess.check_output(
                [str(executable), mode, str(root), *map(str, args)], text=True
            ).splitlines()

        def identify(card):
            return probe("identify", card)

        def available(model, *claimed):
            return probe("available", model, *claimed) == ["1"]

        wired = add_usb(root, 0, "0000", "USBMIC Serial# 041505338", 10)
        wireless = add_usb(root, 1, "0020", "Wireless Mic #081065435", 11)
        other = add_usb(root, 2, "0020", "Wireless Mic #081065436", 12)
        assert identify(0)[:2] == ["1415:0000:041505338", "041505338"]
        assert identify(1)[:2] == ["1415:0020:081065435", "081065435"]
        before = identify(1)
        (wireless / "devnum").write_text("15\n", encoding="ascii")
        assert identify(1)[:3] == before[:3] and identify(1)[3] != before[3]
        assert identify(2)[0] != before[0]

        (other / "product").write_text("Wireless Mic #081065435\n", encoding="ascii")
        assert identify(1)[:2] == identify(2)[:2] == ["", ""]
        for invalid in ("Wireless Mic #08106543x", "Wireless Mic #000000000",
                        "Wireless Mic #081065435 (2)", "USBMIC Serial# 081065435"):
            (other / "product").write_text(invalid + "\n", encoding="ascii")
            assert identify(2)[:2] == ["", ""]
        (wired / "serial").write_text("hardware-serial\n", encoding="ascii")
        assert identify(0)[0] == "1415:0000:hardware-serial"

        mic_a = add_usb(root, 3, "0a03", "USB Microphone", 20, vendor="046d")
        first_a = identify(3)
        model = "046d:0a03"
        assert first_a[:3] == ["", "", model]
        assert probe("attached", first_a[3]) == ["1"]
        assert probe("attached", "") == ["0"]
        assert available(model)
        assert not available(model, first_a[3])
        assert not available("")
        a_attachment = root / "bus" / "usb" / "devices" / mic_a.name
        a_attachment.unlink()
        (mic_a / "devnum").unlink()
        assert probe("attached", first_a[3]) == ["0"]
        assert not available(model, first_a[3])
        a_attachment.symlink_to(mic_a)
        (mic_a / "devnum").write_text("22\n", encoding="ascii")
        returned_a = identify(3)
        assert returned_a[3] != first_a[3]
        assert probe("attached", first_a[3]) == ["0"]
        assert probe("attached", returned_a[3]) == ["1"]
        assert available(model, first_a[3])

        mic_b = add_usb(root, 4, "0a03", "USB Microphone", 21, vendor="046d")
        first_b = identify(4)
        assert first_b[:3] == ["", "", model]
        assert available(model)
        assert available(model, first_b[3])
        assert not available(model, returned_a[3], first_b[3])
        a_attachment.unlink()
        assert not available(model, first_b[3])
        (mic_b / "devnum").write_text("24\n", encoding="ascii")
        assert available(model, first_b[3])
        print("USB capture identity and best-effort candidate checks passed")


if __name__ == "__main__":
    main()
