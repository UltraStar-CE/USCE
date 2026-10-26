#!/usr/bin/env python3
"""Exercise Pascal relay bindings against a bounded native loopback fixture."""
import argparse
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fpc', default='fpc')
    parser.add_argument('--fpc-arg', action='append', default=[])
    parser.add_argument('--build-dir', type=Path, default=Path('build/phone-audio'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    build = args.build_dir.resolve()
    output = build / 'pascal-tests'
    output.mkdir(exist_ok=True)
    extension = '.exe' if sys.platform == 'win32' else ''
    library = ('usce-phone-audio.dll' if sys.platform == 'win32' else
               'libusce-phone-audio.dylib' if sys.platform == 'darwin' else
               'libusce-phone-audio.so')
    fixture = build / ('relay-socket-test' + extension)
    for name, mode in [('relay_socket_test', '--echo-server'),
                       ('relay_session_test', '--session-server')]:
        subprocess.run([args.fpc, *args.fpc_arg, '-Fu' + str(root / 'src/base'),
                        '-FU' + str(output), '-FE' + str(output),
                        str(root / 'tools/tests' / (name + '.pas'))],
                       check=True, timeout=60)
        server = subprocess.Popen([str(fixture), mode], stdout=subprocess.PIPE,
                                  text=True, encoding='utf-8')
        try:
            ready = queue.Queue()
            threading.Thread(target=lambda: ready.put(server.stdout.readline().strip()),
                             daemon=True).start()
            address = ready.get(timeout=5)
            if not re.fullmatch(r'ws://127\.0\.0\.1:\d+/ws/host', address):
                raise RuntimeError('Native fixture did not return a loopback address')
            subprocess.run([str(output / (name + extension)), str(build / library), address],
                           check=True, timeout=15)
            if server.wait(timeout=5) != 0:
                raise RuntimeError('Native fixture failed')
        finally:
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=5)
            server.stdout.close()


if __name__ == '__main__':
    main()
