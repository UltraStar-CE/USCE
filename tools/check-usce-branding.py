"""Check packaging references that must agree across USCE platform builds."""
from pathlib import Path
import plistlib, struct, xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
def read(name):
    return (root / name).read_text(encoding='utf-8-sig')

plist = plistlib.loads((root / 'src/macos/Info.plist').read_bytes())
assert plist['CFBundleExecutable'] == 'usce'
assert plist['CFBundleIconFile'] == 'usce.icns'
assert plist['CFBundleIdentifier'] == 'org.ultrastarce.usce'
assert plist['CFBundleDisplayName'] == 'UltraStar Community Edition'
metadata = ET.parse(root / 'dists/usce.appdata.xml').getroot()
assert metadata.findtext('id') == plist['CFBundleIdentifier']
assert metadata.findtext('launchable') == 'usce.desktop'
for node in metadata.findall('url'):
    assert ' ' not in node.text and 'UltraStar-CE/USCE' in node.text
desktop = read('dists/usce.desktop')
assert '\nExec=usce\n' in desktop and '\nIcon=usce\n' in desktop
assert 'USCE_BIN_NAME ?= usce$(EXEEXT)' in read('src/Makefile.in')
assert 'USCE_PROJ := usce.dpr' in read('src/Makefile.in')
assert 'AC_CONFIG_SRCDIR(src/usce.dpr)' in read('configure.ac')
assert 'program usce;' in read('src/usce.dpr')
assert 'usce.exe.manifest' in read('res/link.rc')
assert 'usce.ico' in read('res/link.rc')
assert 'icons/usce-icon.png' in read('src/base/UGraphic.pas')
assert 'USCE-$(ARCH).AppImage' in read('dists/linux/Makefile')
assert 'usr/bin/usce' in read('dists/linux/tasks.sh')
assert 'usce.png' in read('dists/linux/tasks.sh')
assert 'ultrastardx' not in read('dists/linux/Makefile')
assert 'game/usce' in read('COMPILING.md')
assert '"usce"' in read('installer/settings/variables.nsh')
assert '$APPDATA\\ultrastardx' not in read('installer/UltraStar Community Edition.nsi')
assert '"ultrastardx.exe"' not in read('installer/UltraStar Community Edition.nsi')
assert 'USCE-windows-installer-' in read('.github/workflows/platform-builds.yml')
assert 'USCE-mac-' in read('.github/workflows/platform-builds.yml')
assert 'USCE-linux-' in read('.github/workflows/platform-builds.yml')
assert 'mv USCE*.AppImage' in read('.github/workflows/platform-builds.yml')
for size in (16,32,48,64,128,256,512,1024):
    data=(root / f'icons/usce-icon_{size}.png').read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II',data[16:24]) == (size,size)
ico=(root/'icons/usce.ico').read_bytes()
assert struct.unpack('<HHH',ico[:6]) == (0,1,6)
for offset in range(6,6+16*6,16):
    entry=struct.unpack('<BBBBHHII',ico[offset:offset+16])
    length,start=entry[-2:]
    assert ico[start:start+8] == b'\x89PNG\r\n\x1a\n' and start+length <= len(ico)
icns=(root/'icons/usce.icns').read_bytes()
assert icns[:4] == b'icns' and struct.unpack('>I',icns[4:8])[0] == len(icns)
offset=8
while offset<len(icns):
    length=struct.unpack('>I',icns[offset+4:offset+8])[0]
    assert length>8 and icns[offset+8:offset+16] == b'\x89PNG\r\n\x1a\n'
    offset+=length
assert offset==len(icns)
print('USCE executable, metadata, resource, installer and icon references agree.')
