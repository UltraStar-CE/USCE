"""Package a native /usr-prefix build; no user data or maintainer scripts."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def build(version, output, themes, projectm_prefix):
    if not str(projectm_prefix).strip():
        raise ValueError('Set USCE_PROJECTM_PREFIX for make deb, or pass --projectm-prefix to this script')
    projectm_prefix = Path(projectm_prefix).resolve()
    library = projectm_prefix / 'lib/libprojectM-4.so'
    if not library.is_file():
        raise ValueError(f'Missing projectM 4 shared library: {library}')
    version = version.replace('-dev.', '~dev.')
    if not re.fullmatch(r'[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+(?:[~+][a-zA-Z0-9.+~]+)?', version):
        raise ValueError('Invalid Debian package version')
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    themes = Path(themes).resolve()
    if not (themes / 'Modern.ini').is_file():
        raise ValueError('Missing reviewed theme bundle')
    arch = subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip()
    with tempfile.TemporaryDirectory(prefix='usce-deb-') as temp:
        work = Path(temp)
        stage = work / 'stage'
        subprocess.run(['make', 'DESTDIR=' + str(stage), 'USCE_THEMES_DIR=' + str(themes), 'install'], cwd=ROOT, check=True)
        executable = stage / 'usr/bin/usce'
        if not executable.is_file():
            raise ValueError('Configure with --prefix=/usr before building the package')
        for relative, source in [('usr/share/applications/usce.desktop', ROOT / 'dists/usce.desktop'),
                                 ('usr/share/doc/usce/copyright', ROOT / 'LICENSE')]:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        icon = stage / 'usr/share/icons/hicolor/256x256/apps/usce.png'
        icon.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'icons/usce-icon_256.png', icon)
        soname = subprocess.check_output(['patchelf', '--print-soname', str(library)], text=True).strip()
        match = re.fullmatch(r'(libprojectM-4)\.so\.(\d+)', soname)
        if not match:
            raise ValueError('Unexpected projectM 4 SONAME: ' + soname)
        needed = subprocess.check_output(['patchelf', '--print-needed', str(executable)], text=True).splitlines()
        if soname not in needed or not any(name.startswith('libopencv_videoio.so.') for name in needed):
            raise ValueError('Build USCE with both projectM 4 and OpenCV webcam support')
        bundled_library = stage / 'usr/lib/usce' / soname
        bundled_library.parent.mkdir(parents=True)
        shutil.copyfile(library, bundled_library)
        for license_name in ('copyright', 'hlslparser-license', 'projectm-eval-license', 'soil2-etc1-notice'):
            shutil.copyfile(projectm_prefix / 'share/doc/projectm' / license_name,
                            stage / 'usr/share/doc/usce' / f'projectm-{license_name}')
        shutil.copyfile(ROOT / 'dists/linux/projectm-glm-license.txt',
                        stage / 'usr/share/doc/usce/projectm-glm-license')
        shutil.copyfile('/usr/share/common-licenses/Apache-2.0',
                        stage / 'usr/share/doc/usce/projectm-soil2-etc1-license')
        (work / 'debian').mkdir()
        (work / 'debian/shlibs.local').write_text(f'{match[1]} {match[2]} usce\n')
        (work / 'debian/control').write_text('Source: usce\nSection: games\nPriority: optional\nMaintainer: UltraStar Community Edition contributors <noreply@github.com>\n\nPackage: usce\nArchitecture: any\nDescription: UltraStar Community Edition karaoke game\n')
        receiver = stage / 'usr/bin/libusce-phone-audio.so'
        if not receiver.is_file():
            raise ValueError('Build and stage the native phone receiver before packaging')
        result = subprocess.check_output(['dpkg-shlibdeps', '-O', '-S' + str(stage),
                                          '-l' + str(bundled_library.parent), '-xusce',
                                          '-e' + str(executable), '-e' + str(receiver),
                                          '-e' + str(bundled_library)], cwd=work, text=True)
        subprocess.run(['patchelf', '--set-rpath', '$ORIGIN/../lib/usce', str(executable)], check=True)
        dependencies = result.strip().removeprefix('shlibs:Depends=')
        # These are loaded dynamically and therefore absent from ELF NEEDED.
        linked = {part.strip().split()[0] for part in dependencies.split(',')}
        dependencies += ''.join(', ' + package for package in ['libgl1', 'libsqlite3-0', 'libportaudio2', 'fonts-dejavu-core'] if package not in linked)
        control = stage / 'DEBIAN'
        control.mkdir()
        size = sum(p.stat().st_size for p in stage.rglob('*') if p.is_file()) // 1024
        (control / 'control').write_text(f'Package: usce\nVersion: {version}\nArchitecture: {arch}\nSection: games\nPriority: optional\nMaintainer: UltraStar Community Edition contributors <noreply@github.com>\nDepends: {dependencies}\nInstalled-Size: {size}\nHomepage: https://github.com/UltraStar-CE/USCE\nDescription: UltraStar Community Edition karaoke game\n Sing along with music videos and score your pitch.\n')
        target = output / f'USCE-linux-deb-{version}.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(stage), str(target)], check=True)
        return target

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--themes', required=True)
    parser.add_argument('--projectm-prefix', required=True, help='Installation prefix for the private projectM 4 library and licenses')
    args = parser.parse_args()
    try:
        print(build(args.version, args.output, args.themes, args.projectm_prefix))
    except ValueError as error:
        parser.error(str(error))
