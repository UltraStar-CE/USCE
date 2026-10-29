#!/usr/bin/env python3
"""Detach a packaging volume, allowing for asynchronous macOS unmounts."""
import os
import plistlib
import subprocess
import sys
import time


def detach_volume(hdiutil, mountpoint, run=subprocess.run, sleep=time.sleep, image_path=None):
    target = mountpoint
    expected_image = os.path.realpath(image_path) if image_path else None
    for attempt in range(5):
        result = run([hdiutil, 'detach', target], check=False)
        if result.returncode == 0 and expected_image is None:
            return
        # A failed detach can still unmount the volume asynchronously. Query
        # actual state instead of interpreting localized error messages.
        info = run([hdiutil, 'info', '-plist'], check=True, capture_output=True)
        images = plistlib.loads(info.stdout)['images']
        if expected_image is not None:
            attached = [image for image in images
                        if image.get('image-path') and
                        os.path.realpath(image['image-path']) == expected_image]
            if not attached:
                return
            # Losing the mount point does not mean the backing image is free.
            # Continue detaching its device before hdiutil convert opens it.
            devices = [entity['dev-entry'] for image in attached
                       for entity in image.get('system-entities', [])
                       if entity.get('dev-entry')]
            if devices:
                target = devices[0]
        else:
            mounted = any(entity.get('mount-point') == mountpoint
                          for image in images
                          for entity in image.get('system-entities', []))
            if not mounted:
                return
        if attempt < 4:
            sleep(2)
    raise RuntimeError('Packaging image is still attached: ' + (image_path or mountpoint))


if __name__ == '__main__':
    detach_volume(sys.argv[1], sys.argv[2], image_path=sys.argv[3] if len(sys.argv) > 3 else None)
