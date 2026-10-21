#!/usr/bin/env python3
"""Detach a packaging volume, allowing for asynchronous macOS unmounts."""
import plistlib
import subprocess
import sys
import time


def detach_volume(hdiutil, mountpoint, run=subprocess.run, sleep=time.sleep):
    for attempt in range(5):
        result = run([hdiutil, 'detach', mountpoint], check=False)
        if result.returncode == 0:
            return
        # A failed detach can still unmount the volume asynchronously. Query
        # actual state instead of interpreting localized error messages.
        info = run([hdiutil, 'info', '-plist'], check=True, capture_output=True)
        images = plistlib.loads(info.stdout)['images']
        mounted = any(entity.get('mount-point') == mountpoint
                      for image in images
                      for entity in image.get('system-entities', []))
        if not mounted:
            return
        if attempt < 4:
            sleep(2)
    raise RuntimeError('Packaging volume is still mounted: ' + mountpoint)


if __name__ == '__main__':
    detach_volume(sys.argv[1], sys.argv[2])
