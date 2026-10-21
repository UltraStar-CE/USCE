import plistlib
import subprocess
import unittest
from detach_macos_image import detach_volume


class DetachTests(unittest.TestCase):
    def simulate(self, replies):
        calls = []
        def run(args, **kwargs):
            calls.append(args[1:])
            reply = replies.pop(0)
            if isinstance(reply, Exception):
                raise reply
            return subprocess.CompletedProcess(args, reply[0], reply[1])
        return calls, run

    def test_success(self):
        calls, run = self.simulate([(0, b'')])
        detach_volume('hdiutil', '/volume', run, lambda _: None)
        self.assertEqual(calls, [['detach', '/volume']])

    def test_failed_detach_but_already_unmounted(self):
        calls, run = self.simulate([(1, b''), (0, plistlib.dumps({'images': []}))])
        detach_volume('hdiutil', '/volume', run, lambda _: None)
        self.assertEqual(len(calls), 2)

    def test_busy_volume_retries_and_fails(self):
        mounted = plistlib.dumps({'images': [{'system-entities': [{'mount-point': '/volume'}]}]})
        calls, run = self.simulate([(1, b''), (0, mounted)] * 5)
        with self.assertRaises(RuntimeError):
            detach_volume('hdiutil', '/volume', run, lambda _: None)
        self.assertEqual(len(calls), 10)

    def test_unreadable_state_fails(self):
        calls, run = self.simulate([(1, b''), subprocess.CalledProcessError(1, 'info')])
        with self.assertRaises(subprocess.CalledProcessError):
            detach_volume('hdiutil', '/volume', run, lambda _: None)


if __name__ == '__main__':
    unittest.main()
