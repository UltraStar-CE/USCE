"""Stage the reviewed Themes snapshot without modifying the game checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'UltraStar-CE/Themes'
METADATA = {'.git', '.github', '.gitignore', '.gitattributes'}


def read_pin(path):
    pin = json.loads(Path(path).read_text(encoding='utf-8'))
    if pin.get('repository') != REPOSITORY or not re.fullmatch(r'[0-9a-f]{40}', pin.get('sha', '')):
        raise ValueError('Themes must use a full commit SHA from UltraStar-CE/Themes')
    return pin


def bundle(source, destination, pin):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if sha != pin['sha']:
        raise ValueError('Themes checkout does not match the reviewed commit')
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain', '--untracked-files=all'], text=True):
        raise ValueError('Themes checkout must match its committed contents')
    if destination == source or source in destination.parents or destination in source.parents:
        raise ValueError('Theme source and bundle must be separate directories')
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError('Theme bundle destination must be empty')
    files = []
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source)
        if any(part in METADATA for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError('Theme assets must be regular files, not symlinks')
        if path.is_file():
            files.append((path, relative))
    themes = sorted(path.name for path in source.glob('*.ini') if path.is_file())
    if not themes:
        raise ValueError('Themes snapshot contains no theme definitions')
    destination.mkdir(parents=True, exist_ok=True)
    inventory = []
    for path, relative in files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(path), str(target))
        inventory.append({'path': relative.as_posix(), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    manifest = {'repository': REPOSITORY, 'sha': sha, 'themes': themes, 'files': inventory}
    (destination / 'BUNDLE-SOURCE.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


def portable(game, themes, destination, pin):
    game, themes, destination = Path(game).resolve(), Path(themes).resolve(), Path(destination).resolve()
    manifest = json.loads((themes / 'BUNDLE-SOURCE.json').read_text(encoding='utf-8'))
    if manifest['repository'] != pin['repository'] or manifest['sha'] != pin['sha']:
        raise ValueError('Portable themes do not match the reviewed commit')
    if not (game / 'usce.exe').is_file():
        raise ValueError('Portable source must contain usce.exe')
    for source in [game, themes]:
        if destination == source or source in destination.parents or destination in source.parents:
            raise ValueError('Portable destination must be separate from its sources')
    if destination.exists():
        raise ValueError('Portable destination must not already exist')
    shutil.copytree(str(game), str(destination), ignore=lambda directory, names: ['themes'] if Path(directory) == game else [])
    shutil.copytree(str(themes), str(destination / 'themes'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['pin', 'bundle', 'portable'])
    parser.add_argument('--pin', default=str(ROOT / 'themes.json'))
    parser.add_argument('--source', default=str(ROOT / '.release-themes/source'))
    parser.add_argument('--destination', default=str(ROOT / '.release-themes/bundle'))
    parser.add_argument('--themes', default=str(ROOT / '.release-themes/bundle'))
    args = parser.parse_args()
    pin = read_pin(args.pin)
    if args.command == 'pin':
        print('sha=' + pin['sha'])
    elif args.command == 'bundle':
        manifest = bundle(args.source, args.destination, pin)
        print('Bundled {} themes from {}'.format(len(manifest['themes']), manifest['sha']))
    else:
        portable(args.source, args.themes, args.destination, pin)
