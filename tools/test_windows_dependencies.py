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
    def run_prerequisite_check(self, missing_tool='', meson_exit='0', task=False,
                               existing_prefix=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copyfile(SCRIPT.parent / 'check-tools.sh', root / 'check-tools.sh')
            shutil.copyfile(SCRIPT, root / 'tasks.sh')
            sentinel = root / 'prefix' / 'previous-build.txt'
            if existing_prefix:
                sentinel.parent.mkdir()
                sentinel.write_text('keep', encoding='utf-8')
            env = dict(os.environ, MISSING_TOOL=missing_tool, MESON_EXIT=meson_exit)
            # Simulate tool discovery, including an old patch available on PATH.
            harness = '''
command() {
    if [[ "$1" != -v ]]; then builtin command "$@"; return; fi
    if [[ "$2" == "$MISSING_TOOL" ]]; then return 1; fi
    if [[ "$2" == patch ]]; then
        printf '%s\\n' 'C:/FPC/bin/patch'
    else
        printf '%s\\n' "$2"
    fi
}
meson() { return "$MESON_EXIT"; }
export -f command meson
'''
            task_name = task if isinstance(task, str) else 'dl'
            harness += ('source ./tasks.sh ' + task_name if task
                        else 'source ./check-tools.sh')
            result = subprocess.run([BASH, '-c', harness], cwd=directory,
                                    env=env, capture_output=True, text=True)
            self.assertFalse((root / 'deps').exists(), result.stdout + result.stderr)
            if existing_prefix:
                self.assertEqual(sentinel.read_text(encoding='utf-8'), 'keep')
            else:
                self.assertFalse((root / 'prefix').exists(), result.stdout + result.stderr)
            return result

    @unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required')
    def test_old_fpc_patch_does_not_replace_missing_msys_patch(self):
        result = self.run_prerequisite_check(missing_tool='/usr/bin/patch', task=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('/usr/bin/patch', result.stderr)
        self.assertIn('pacman -S --needed patch', result.stderr)

    @unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required')
    def test_missing_nasm_is_reported_before_download(self):
        result = self.run_prerequisite_check(missing_tool='nasm', task=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('mingw-w64-ucrt-x86_64-nasm', result.stderr)

    @unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required')
    def test_missing_tool_preserves_previous_dependency_build(self):
        result = self.run_prerequisite_check(missing_tool='nasm', task='all_deps',
                                            existing_prefix=True)
        self.assertNotEqual(result.returncode, 0)

    @unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required')
    def test_broken_meson_launcher_fails_early(self):
        result = self.run_prerequisite_check(meson_exit='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Meson cannot run', result.stderr)

    @unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required')
    def test_complete_toolchain_passes_without_modifying_build(self):
        result = self.run_prerequisite_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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
