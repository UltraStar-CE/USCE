#!/usr/bin/env python3
"""Stage the native receiver and its third-party notices for game packaging."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil

ROOT = Path(__file__).resolve().parent.parent


def stage(build, game, system, openssl_licenses):
    names = {'windows':'usce-phone-audio.dll', 'darwin':'libusce-phone-audio.dylib', 'linux':'libusce-phone-audio.so'}
    library = build / names[system]
    if not library.is_file():
        raise ValueError(f'Native receiver has not been built: {library}')
    cache = {}
    for line in (build / 'CMakeCache.txt').read_text().splitlines():
        if '=' in line and ':' in line.split('=', 1)[0] and not line.startswith(('#','//')):
            key, value = line.split('=', 1)
            cache[key.split(':', 1)[0]] = value
    source = Path(cache.get('usce_phone_audio_SOURCE_DIR', '')).resolve()
    if source != (ROOT / 'native/phone-audio').resolve():
        raise ValueError('Native build does not match this source checkout')
    notices = [
        'Native phone audio: third-party notices',
        'libdatachannel source: https://github.com/paullouisageneau/libdatachannel/tree/6b1e2e620f1e37f0eafeee702eaea0043cb305fd',
        'Its libjuice, plog and usrsctp submodules are pinned by that source revision.',
        'nlohmann/json source: https://github.com/nlohmann/json/releases/tag/v3.12.0',
    ]
    for component in ['libdatachannel','libjuice','plog','usrsctplib','nlohmann_json']:
        directory = Path(cache.get(component + '_SOURCE_DIR', ''))
        licenses = sorted(path for path in directory.glob('*') if path.is_file() and path.name.upper().startswith(('LICENSE','COPYING')))
        if not licenses:
            raise ValueError(f'Missing {component} license in native build')
        for license_file in licenses:
            notices += [f'\n--- {component}: {license_file.name} ---\n', license_file.read_text(encoding='utf-8', errors='replace')]
    if not openssl_licenses:
        raise ValueError('Pass the OpenSSL package license used for this build')
    for license_file in openssl_licenses:
        if not license_file.is_file():
            raise ValueError(f'Missing OpenSSL license: {license_file}')
        notices += ['\n--- OpenSSL ---\n', license_file.read_text(encoding='utf-8', errors='replace')]
    game.mkdir(parents=True, exist_ok=True)
    shutil.copy2(library, game / library.name)
    runtime = game / 'runtime'
    runtime.mkdir(exist_ok=True)
    (runtime / 'native-licenses.txt').write_text('\n'.join(notices) + '\n', encoding='utf-8')
    metadata = {'library':library.name, 'sha256':hashlib.sha256(library.read_bytes()).hexdigest(),
                'staticOpenSSL':cache.get('OPENSSL_USE_STATIC_LIBS') == 'TRUE'}
    (runtime / 'phone-audio.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Staged {library.name}, provenance and third-party notices')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, default=ROOT / 'build/phone-audio')
    parser.add_argument('--game', type=Path, default=ROOT / 'game')
    parser.add_argument('--platform', default=platform.system().lower(), choices=['windows','darwin','linux'])
    parser.add_argument('--openssl-license', type=Path, action='append', required=True)
    args = parser.parse_args()
    stage(args.build, args.game, args.platform, args.openssl_license)
