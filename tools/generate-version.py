"""Generate build versions without changing the tracked release base."""
from __future__ import print_function
import argparse, json, os, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def git(*args):
    return subprocess.check_output(['git'] + list(args), cwd=str(ROOT), stderr=subprocess.DEVNULL).decode('utf-8').strip()

def version_info(base, sha, distance, dirty=False, release=None):
    if not re.match(r'^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$', base) or not 1 <= int(base.split('.')[1]) <= 12:
        raise ValueError('Invalid calendar version')
    if sha is not None and not re.match(r'^[a-f0-9]{40}$', sha):
        raise ValueError('Invalid source revision')
    if release is not None and (release != base or dirty or sha is None):
        raise ValueError('Release version must match VERSION and the checkout must be clean')
    full = base if release is not None else '{}-dev.{}+g{}{}'.format(base, distance, sha[:12] if sha else 'unknown', '.dirty' if dirty else '')
    return {'base': base, 'version': full, 'sha': sha, 'stable': release is not None}

def generate():
    base = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
    try:
        if Path(git('rev-parse', '--show-toplevel')).resolve() != ROOT:
            raise OSError('Source archive is not the Git repository root')
        sha = git('rev-parse', 'HEAD')
        distance = int(git('rev-list', '--count', 'HEAD'))
        dirty = bool(git('status', '--porcelain', '--untracked-files=no'))
    except (subprocess.CalledProcessError, OSError):
        sha, distance, dirty = None, 0, False
    release = os.environ.get('USCE_RELEASE_VERSION') or None
    if sha and not dirty and not release and os.environ.get('USCE_BUILD_CHANNEL') != 'development':
        try:
            if git('describe', '--exact-match', '--tags', '--match', 'v' + base) == 'v' + base:
                release = base
        except subprocess.CalledProcessError:
            pass
    info = version_info(base, sha, distance, dirty, release)
    (ROOT / 'VERSION.build').write_text(info['version'] + '\n', encoding='utf-8')
    (ROOT / 'src/base/usce-version.inc').write_text("'{}'".format(info['version']), encoding='utf-8')
    stable = info['stable']
    values = {'VersionStr': base, 'FullVersion': info['version'], 'Release': 'Stable' if stable else 'Dev',
              'ReleaseMeta': '+stable' if stable else '+dev', 'ReleaseApp': ' Stable' if stable else ' Dev'}
    nsis = ''.join('!define {} "{}"\n'.format(k,v) for k,v in values.items())
    nsis += '!define DevBuild {}\n'.format('false' if stable else 'true')
    (ROOT / 'installer/settings/version.nsh').write_text(nsis, encoding='utf-8')
    text = (ROOT / 'src/macos/Info.plist.in').read_text(encoding='utf-8').replace('@USCE_NUMERIC_VERSION@', base).replace('@USCE_FULL_VERSION@', info['version'])
    (ROOT / 'src/macos/Info.plist').write_text(text, encoding='utf-8')
    (ROOT / 'build-version.json').write_text(json.dumps(info, sort_keys=True) + '\n', encoding='utf-8')
    print(info['version'])

if __name__ == '__main__':
    generate()
