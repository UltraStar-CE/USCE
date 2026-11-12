import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('windows_runtime', Path(__file__).with_name('check_windows_runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def fixture(wide, delayed=False):
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 64)
    data[64:68] = b'PE\0\0'
    optional = 88
    optional_size = 240 if wide else 224
    struct.pack_into('<H', data, 70, 1)
    struct.pack_into('<H', data, 84, optional_size)
    struct.pack_into('<H', data, optional, 0x20b if wide else 0x10b)
    directories = optional + (112 if wide else 96)
    struct.pack_into('<I', data, directories - 4, 16)
    struct.pack_into('<IIII', data, optional + optional_size + 8, 512, 4096, 512, 512)
    index = 13 if delayed else 1
    struct.pack_into('<II', data, directories + index * 8, 4096, 64 if delayed else 40)
    struct.pack_into('<I', data, 512 + (4 if delayed else 12), 4196)
    if delayed:
        struct.pack_into('<I', data, 512, 1)
    data[612:625] = b'example.dll\0\0'
    return data


class WindowsRuntimeTests(unittest.TestCase):
    def test_imports_cover_both_pe_formats_and_delay_imports(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.exe'
            for wide in (False, True):
                for delayed in (False, True):
                    path.write_bytes(fixture(wide, delayed))
                    self.assertEqual(runtime.imports(path), {'example.dll'})

    def test_truncated_or_invalid_import_metadata_fails_with_filename(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'broken.dll'
            for data in (b'not a PE', fixture(True)[:100]):
                path.write_bytes(data)
                with self.assertRaisesRegex(ValueError, 'broken.dll: invalid PE'):
                    runtime.imports(path)
