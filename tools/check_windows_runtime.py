"""Check PE imports and load every packaged DLL using only its directory/System32."""
import argparse
import ctypes
from ctypes import wintypes
import os
from pathlib import Path, PureWindowsPath
import struct


def imports(path):
    data = Path(path).read_bytes()
    try:
        if data[:2] != b'MZ':
            raise ValueError('missing DOS header')
        pe = struct.unpack_from('<I', data, 60)[0]
        if data[pe:pe + 4] != b'PE\0\0':
            raise ValueError('missing PE signature')
        count = struct.unpack_from('<H', data, pe + 6)[0]
        optional_size = struct.unpack_from('<H', data, pe + 20)[0]
        optional = pe + 24
        magic = struct.unpack_from('<H', data, optional)[0]
        if magic not in (0x10b, 0x20b):
            raise ValueError('unknown PE optional header')
        directories = optional + (112 if magic == 0x20b else 96)
        directory_count = struct.unpack_from('<I', data, directories - 4)[0]
        image_base = struct.unpack_from('<Q' if magic == 0x20b else '<I', data,
                                        optional + (24 if magic == 0x20b else 28))[0]
        sections = [struct.unpack_from('<IIII', data, optional + optional_size + i * 40 + 8)
                    for i in range(count)]

        def offset(rva):
            for size, address, raw_size, raw in sections:
                if address <= rva < address + raw_size:
                    return raw + rva - address
            raise ValueError('import RVA is outside section data')

        names = set()
        for index, stride, name_field in ((1, 20, 3), (13, 32, 1)):
            if index >= directory_count:
                continue
            rva, size = struct.unpack_from('<II', data, directories + index * 8)
            if not rva:
                continue
            start = offset(rva)
            for position in range(start, start + size, stride):
                descriptor = struct.unpack_from('<' + 'I' * (stride // 4), data, position)
                if not any(descriptor):
                    break
                name_rva = descriptor[name_field]
                if index == 13 and not descriptor[0] & 1:
                    name_rva -= image_base
                name_start = offset(name_rva)
                end = data.find(b'\0', name_start, name_start + 512)
                if end < 0:
                    raise ValueError('unterminated DLL name')
                name = data[name_start:end].decode('ascii')
                if PureWindowsPath(name).name != name:
                    raise ValueError('import name contains a path')
                names.add(name)
            else:
                raise ValueError('unterminated import directory')
        return names
    except (struct.error, UnicodeError, ValueError) as error:
        raise ValueError(str(path) + ': invalid PE imports: ' + str(error)) from error


def check(package):
    if os.name != 'nt':
        raise RuntimeError('DLL loading must be checked on Windows')
    package = Path(package).resolve()
    executable = package / 'usce.exe'
    if not executable.is_file():
        raise ValueError('Missing packaged executable: ' + str(executable))
    libraries = {p.name.lower(): p for p in package.iterdir() if p.suffix.lower() == '.dll'}
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    kernel.LoadLibraryExW.restype = wintypes.HMODULE
    kernel.FreeLibrary.argtypes = [wintypes.HMODULE]
    kernel.GetModuleFileNameW.argtypes = [wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]
    kernel.GetSystemDirectoryW.argtypes = [wintypes.LPWSTR, wintypes.UINT]
    kernel.SetDefaultDllDirectories.argtypes = [wintypes.DWORD]
    kernel.SetDefaultDllDirectories.restype = wintypes.BOOL
    kernel.SetErrorMode(0x8001)  # no blocking loader error dialogs in CI
    if not kernel.SetDefaultDllDirectories(0x800):
        raise ctypes.WinError(ctypes.get_last_error())
    system_buffer = ctypes.create_unicode_buffer(32768)
    if not kernel.GetSystemDirectoryW(system_buffer, len(system_buffer)):
        raise ctypes.WinError(ctypes.get_last_error())
    system = Path(system_buffer.value).resolve()
    side_by_side = system.parent / 'WinSxS'
    handles = []
    loaded = set()

    def load(name, importer):
        if name.lower() in loaded:
            return
        path = libraries.get(name.lower())
        # DLL_LOAD_DIR | SYSTEM32 for a package DLL, SYSTEM32 for a system import.
        handle = kernel.LoadLibraryExW(str(path) if path else name, None, 0x900 if path else 0x800)
        if not handle:
            raise RuntimeError(f'{importer}: cannot load {name}: ' +
                               str(ctypes.WinError(ctypes.get_last_error())))
        handles.append(handle)
        resolved = ctypes.create_unicode_buffer(32768)
        if not kernel.GetModuleFileNameW(handle, resolved, len(resolved)):
            raise ctypes.WinError(ctypes.get_last_error())
        actual = Path(resolved.value).resolve()
        if actual.parent != package and actual.parent != system and side_by_side not in actual.parents:
            raise RuntimeError(f'{importer}: {name} was supplied outside the package/Windows: {actual}')
        loaded.add(name.lower())

    try:
        # Enumerating every PE import also catches a missing DLL that Python/MSYS2
        # happened to load before the restricted search policy was installed.
        required = {}
        for binary in [executable, *libraries.values()]:
            for dependency in sorted(imports(binary)):
                required.setdefault(dependency.lower(), binary.name)
        # Resolve absent package imports first, so a missing transitive runtime
        # is named directly rather than reported as a generic parent load failure.
        for dependency, importer in sorted(required.items()):
            if dependency not in libraries:
                load(dependency, importer)
        for name in sorted(libraries):
            load(name, 'packaged DLL')
        print(f'PASS: {len(libraries)} packaged DLLs and {len(required)} distinct imports load without PATH')
    finally:
        for handle in reversed(handles):
            kernel.FreeLibrary(handle)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    args = parser.parse_args()
    check(args.package)
