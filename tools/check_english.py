#!/usr/bin/env python3
"""Check English fallback coverage without running the game or its plugins."""
import argparse
import re
from collections import defaultdict
from pathlib import Path

KEY = re.compile(r"[A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9]\Z")
PASCAL = re.compile(r"'(?:''|[^'])*'|//[^\n]*|\{.*?\}|\(\*.*?\*\)", re.S)
LUA = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|--\[\[.*?\]\]|--[^\n]*", re.S)


def without_comments(text, pattern):
    return pattern.sub(lambda m: m[0] if m[0].startswith(("'", '"'))
                       else re.sub(r'[^\n]', ' ', m[0]), text)


def read_english(path):
    entries, errors, section = {}, [], ''
    for line_no, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        line = line.strip()
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1].lower()
        elif section == 'text' and '=' in line and not line.startswith((';', '#', '//')):
            key, value = (part.strip() for part in line.split('=', 1))
            key = key.upper()
            if key in entries:
                errors.append(f'{path}:{line_no}: duplicate English key {key}')
            entries[key] = value
    if not entries:
        errors.append(f'{path}: missing or empty [Text] section')
    return entries, errors


def audit(root, extra_themes=()):
    entries, errors = read_english(root / 'game/languages/English.ini')
    prefixes = {key.split('_')[0] for key in entries if '_' in key}
    references = defaultdict(set)
    constants = set()
    sources = {}

    def add(key, path, line):
        references[key.upper()].add(f'{path}:{line}')

    for path in sorted((root / 'src').rglob('*.pas')):
        relative = path.relative_to(root)
        if any(part in ('lib', 'webSDK') for part in relative.parts):
            continue
        text = without_comments(path.read_text(encoding='utf-8-sig', errors='replace'), PASCAL)
        sources[relative.as_posix()] = text
        constants.update(match.upper() for match in re.findall(
            r"\bLanguage\.AddConst\s*\(\s*'([A-Z0-9_]+)'", text, re.I))
        # Literal calls also cover new translation prefixes not yet present in English.
        for match in re.finditer(r"\bLanguage\.Translate\s*\(\s*'([A-Z0-9_]+)'\s*\)", text, re.I):
            if KEY.fullmatch(match[1].upper()) or match[1].upper() in entries:
                add(match[1], relative, text.count('\n', 0, match.start()) + 1)
        # Keys also reach Translate through popup/helper arguments and constant arrays.
        for match in re.finditer(r"'([A-Z][A-Z0-9_]+)'", text):
            key = match[1]
            if KEY.fullmatch(key) and key.split('_')[0] in prefixes:
                add(key, relative, text.count('\n', 0, match.start()) + 1)

    ini_source = sources.get('src/base/UIni.pas', '')
    if "'OPTION_PLAYER_'" in ini_source:
        limit = re.search(r'\bIMaxPlayerCount\s*=\s*(\d+)\s*;', ini_source)
        if not limit:
            errors.append('Cannot determine IMaxPlayerCount for generated player labels')
        else:
            for player in range(1, int(limit[1]) + 1):
                add(f'OPTION_PLAYER_{player}', 'src/base/UIni.pas', 'generated')

    for path in sorted((root / 'game/plugins').rglob('*.usdx')):
        text = without_comments(path.read_text(encoding='utf-8-sig', errors='replace'), LUA)
        for match in re.finditer(r"\bMode\.Name\s*=\s*(['\"])([A-Za-z0-9_]+)\1", text):
            for suffix in ('NAME', 'DESC'):
                add(f'MODE_{match[2].upper()}_{suffix}', path.relative_to(root),
                    text.count('\n', 0, match.start()) + 1)

    for folder in (root / 'game/themes', *extra_themes):
        if not folder.is_dir():
            errors.append(f'{folder}: theme directory does not exist')
            continue
        for path in sorted(folder.rglob('*.ini')):
            section = ''
            for number, line in enumerate(path.read_text(encoding='utf-8-sig', errors='replace').splitlines(), 1):
                line = line.strip()
                if line.startswith('[') and line.endswith(']'):
                    section = line[1:-1]
                match = re.fullmatch(r'Text\s*=\s*([A-Z][A-Z0-9_]*)', line, re.I)
                if not match or not KEY.fullmatch(match[1]):
                    continue
                key = match[1]
                # UScreenPartyRounds replaces these seven captions before display
                # with Format(Translate('PARTY_SELECTMODE'), [round]).
                slot = re.fullmatch(r'PartyRoundsSelectRound([1-7])', section, re.I)
                if slot and key == f'PARTY_SELECTMODE{slot[1]}':
                    continue
                add(key, path, number)

    for key, sites in sorted(references.items()):
        if key not in constants and not entries.get(key):
            errors.append(f'{key}: missing or empty English text ({", ".join(sorted(sites)[:3])})')
    return errors, len(references)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--themes', action='append', type=Path, default=[],
                        help='Also scan a checked-out, pinned Themes package')
    args = parser.parse_args()
    errors, count = audit(args.root, args.themes)
    for error in errors:
        print(error)
    print(f'Checked {count} English keys from source literals, generated player labels, '
          f'bundled party modes and theme text; {len(errors)} errors.')
    print('Arbitrary runtime/plugin-generated text still needs an in-game check.')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
