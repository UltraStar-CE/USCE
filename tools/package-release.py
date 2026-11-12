"""Collect exact-version release artifacts and checksum the six downloads."""
import hashlib, json, re, sys, zipfile
from pathlib import Path

def package(source, dest, version):
    if not re.fullmatch(r'[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+', version):
        raise ValueError('Invalid release version')
    source, dest = Path(source), Path(dest)
    if dest.exists() and list(dest.iterdir()):
        raise ValueError('Release output directory must be empty')
    dest.mkdir(parents=True, exist_ok=True)
    names = {'USCE-windows-installer-' + version: '.exe', 'USCE-windows-portable-' + version: '.zip',
             'USCE-linux-' + version: '.AppImage', 'USCE-linux-deb-' + version: '.deb', 'USCE-mac-ARM-' + version: '.dmg', 'USCE-mac-x86-' + version: '.dmg'}
    if set(p.name for p in source.iterdir()) != set(names):
        raise ValueError('Expected exactly the six matching platform artifacts')
    for name, ext in names.items():
        directory = source / name
        files = sorted(p for p in directory.rglob('*') if p.is_file())
        if not files or any(p.is_symlink() for p in directory.rglob('*')):
            raise ValueError('Missing or unsupported artifact contents')
        target = dest / (name + ext)
        if ext == '.zip':
            if not (directory / 'usce.exe').is_file():
                raise ValueError('Portable artifact is missing the game executable')
            with zipfile.ZipFile(str(target), 'w', zipfile.ZIP_DEFLATED) as archive:
                for p in files:
                    # Artifact extraction times change on retries. Keep ZIP bytes stable.
                    entry = zipfile.ZipInfo(p.relative_to(directory).as_posix(), (1980, 1, 1, 0, 0, 0))
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    entry.external_attr = 0o100644 << 16
                    archive.writestr(entry, p.read_bytes())
        else:
            if len(files) != 1 or files[0].name != target.name:
                raise ValueError('Platform artifact name does not match the release')
            target.write_bytes(files[0].read_bytes())
    (dest / 'VERSION').write_text(version + '\n')
    manifest = [{'name': p.name, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(dest.iterdir())]
    (dest / 'SHA256SUMS').write_text(''.join('{}  {}\n'.format(p['sha256'], p['name']) for p in manifest))
    return manifest

if __name__ == '__main__':
    package(sys.argv[1], sys.argv[2], sys.argv[3])
