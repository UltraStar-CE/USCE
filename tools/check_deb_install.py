"""Exercise package install, upgrade and removal in a disposable dpkg root."""
from pathlib import Path
import subprocess
import os
import sys
import tempfile

package = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='usce-deb-test-') as temp:
    root = Path(temp) / 'root'
    admin = root / 'var/lib/dpkg'
    admin.mkdir(parents=True)
    (admin / 'status').touch()
    fixture = root / 'home/singer/.usce'
    fixture.mkdir(parents=True)
    for name in ['config.ini', 'scores.db', 'songs/example.txt']:
        target = fixture / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('user data')
    listing = subprocess.check_output(['dpkg-deb', '--contents', str(package)], text=True)
    if any(name in listing for name in ['./home/', './etc/', './usr/local/']):
        raise RuntimeError('Package must not install user data or /usr/local files')
    os.environ['NEEDRESTART_SUSPEND'] = '1'
    (root / 'var/log').mkdir(parents=True)
    command = ['dpkg', '--log=' + str(root / 'var/log/dpkg.log'), '--no-triggers', '--root=' + str(root), '--force-not-root', '--force-bad-path', '--force-depends']
    subprocess.run(command + ['--install', str(package)], check=True)
    assert (root / 'usr/bin/usce').is_file()
    assert (root / 'usr/share/applications/usce.desktop').is_file()
    unpack = Path(temp) / 'upgrade'
    subprocess.run(['dpkg-deb', '--raw-extract', str(package), str(unpack)], check=True)
    assert set(p.name for p in (unpack / 'DEBIAN').iterdir()) <= {'control', 'md5sums'}
    control = unpack / 'DEBIAN/control'
    text = control.read_text()
    text = '\n'.join(line + '+upgrade' if line.startswith('Version:') else line for line in text.splitlines()) + '\n'
    control.write_text(text)
    upgrade = Path(temp) / 'upgrade.deb'
    subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(unpack), str(upgrade)], check=True)
    subprocess.run(command + ['--install', str(upgrade)], check=True)
    subprocess.run(command + ['--purge', 'usce'], check=True)
    assert not (root / 'usr/bin/usce').exists()
    for name in ['config.ini', 'scores.db', 'songs/example.txt']:
        assert (fixture / name).read_text() == 'user data'
print('PASS install, upgrade, purge and user-data preservation in isolated dpkg root')
