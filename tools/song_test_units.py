"""Find Pascal units for the configured song regression build."""
import os
import re
import subprocess
import sys


def unit_flags(src):
    target = {'darwin': 'darwin', 'win32': 'win'}.get(sys.platform, 'linux')
    if sys.platform.startswith('freebsd'):
        target = 'freebsd'
    config = src / f'config-{target}.inc'
    if not config.is_file():
        raise SystemExit(f'Run autogen.sh and configure first (missing {config.name})')
    if os.name != 'nt' and not (src / 'paths.inc').is_file():
        subprocess.run(['make', 'create-pathinfo'], cwd=src, check=True)
    binding = re.search(r"\bDEFINE FFMPEG_DIR\s*:=\s*'([^']+)'", config.read_text(encoding='utf-8'))
    ffmpeg = binding[1] if binding else None
    directories = {path.parent for path in src.rglob('*.pas')
                   if 'ctypes' not in path.parts and not any(
                       part.startswith('ffmpeg-') and part != ffmpeg for part in path.parts)}
    flags = ['-Fu' + str(directory) for directory in sorted(directories)]
    return (['-Px86_64', '-WC'] if os.name == 'nt' else []) + flags
