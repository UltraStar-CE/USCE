import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'dists/windows/tasks.sh'
BASH = (r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt'
        else shutil.which('bash'))


class WindowsDependencyTests(unittest.TestCase):
    @unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required')
    def test_runtime_dependencies_from_each_dll_are_packaged(self):
        source = SCRIPT.read_text(encoding='utf-8')
        start = source.index('copy_msys2_dlls() {')
        end = source.index('\n}', start) + 2
        function = source[start:end]
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'check.sh'
            script.write_text('''set -e
PREFIX=$(pwd)/prefix
MINGW_PREFIX=$(pwd)/ucrt64
mkdir -p "$PREFIX/bin" "$MINGW_PREFIX/bin"
touch "$PREFIX/bin/first.dll" "$PREFIX/bin/second.dll"
printf first > "$MINGW_PREFIX/bin/first-runtime.dll"
printf second > "$MINGW_PREFIX/bin/second-runtime.dll"
ldd() {
    case "$1" in
    *first.dll) echo "first-runtime.dll => $MINGW_PREFIX/bin/first-runtime.dll (0x0)";;
    *second.dll) echo "second-runtime.dll => $MINGW_PREFIX/bin/second-runtime.dll (0x0)";;
    esac
}
''' + function + '''
copy_msys2_dlls 'first second'
test "$(cat "$PREFIX/bin/msys2/first-runtime.dll")" = first
test "$(cat "$PREFIX/bin/msys2/second-runtime.dll")" = second
''', encoding='utf-8', newline='\n')
            result = subprocess.run([BASH, str(script)], cwd=directory,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
