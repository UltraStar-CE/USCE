import gzip
import importlib.util
import json
import os
from pathlib import Path
try:
    import pwd
except ImportError:
    pwd = None
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("apt_repository", Path(__file__).with_name("apt-repository.py"))
apt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apt)

class Releases(unittest.TestCase):
    def test_collect_checks_hashes_and_ignores_drafts(self):
        import hashlib
        payload = b"fixture deb bytes"
        name = "USCE-linux-deb-2026.10.0.deb"
        release = {"tag_name": "v2026.10.0", "draft": False, "prerelease": False,
                   "assets": [{"id": 1, "name": name, "size": len(payload)},
                              {"id": 2, "name": "SHA256SUMS", "size": 200}]}
        sums = (hashlib.sha256(payload).hexdigest() + "  " + name + "\n").encode()
        def response(args, **kwargs):
            if "--paginate" in args:
                return json.dumps([[dict(release, draft=True)], [release]])
            return sums if args[-1].endswith("/2") else payload
        with tempfile.TemporaryDirectory() as d, patch.object(apt.subprocess, "check_output", side_effect=response):
            apt.collect(Path(d) / "downloads", "v2026.10.0")
            self.assertEqual((Path(d) / "downloads/usce_2026.10.0_amd64.deb").read_bytes(), payload)
        with tempfile.TemporaryDirectory() as d, patch.object(apt.subprocess, "check_output", side_effect=response):
            with self.assertRaises(ValueError):
                apt.collect(Path(d) / "downloads", "v2026.11.0")
        def damaged(args, **kwargs):
            return b"wrong bytes" if args[-1].endswith("/1") else response(args, **kwargs)
        with tempfile.TemporaryDirectory() as d, patch.object(apt.subprocess, "check_output", side_effect=damaged):
            with self.assertRaisesRegex(ValueError, "checksum"):
                apt.collect(Path(d) / "downloads")

@unittest.skipUnless(all(shutil.which(t) for t in ["dpkg-deb", "dpkg-scanpackages", "apt-ftparchive", "gpg", "gpgv", "apt-get"]),
                     "Native APT/GnuPG tools required (installed by apt-repository-check.yml)")
class NativeRepository(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.packages = self.root / "packages"
        self.packages.mkdir()

    def package(self, version, arch="amd64"):
        stage = self.root / ("stage-" + version + arch)
        (stage / "DEBIAN").mkdir(parents=True)
        (stage / "DEBIAN/control").write_text(f"Package: usce\nVersion: {version}\nArchitecture: {arch}\nMaintainer: Test <test@example.invalid>\nDescription: Test package, never executed\n")
        (stage / "usr/share/usce").mkdir(parents=True)
        (stage / "usr/share/usce/test.txt").write_text(version)
        target = self.packages / (version + arch + ".deb")
        subprocess.run(["dpkg-deb", "--build", "--root-owner-group", str(stage), str(target)], check=True,
                       stdout=subprocess.DEVNULL)
        return target

    def test_rejects_wrong_architecture(self):
        self.package("2026.10.0", "arm64")
        with self.assertRaises(ValueError):
            apt.build(self.packages, self.root / "site")

    def test_signed_repository_with_real_apt_client(self):
        self.package("2026.10.0")
        self.package("2026.10.1")
        site = self.root / "site"
        repo = apt.build(self.packages, site)
        packages = gzip.decompress((repo / "dists/jammy/main/binary-amd64/Packages.gz").read_bytes())
        self.assertEqual(packages.count(b"Package: usce"), 2)
        home = self.root / "gnupg"; home.mkdir(mode=0o700)
        with patch.dict(os.environ, {"GNUPGHOME": str(home)}):
            try:
                subprocess.run(["gpg", "--batch", "--passphrase", "", "--quick-generate-key",
                                "APT test <test@example.invalid>", "ed25519", "sign", "1d"], check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                listing = subprocess.check_output(["gpg", "--with-colons", "--list-secret-keys"], text=True)
                fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
                secret = subprocess.check_output(["gpg", "--armor", "--export-secret-keys", fingerprint]).decode()
                with patch.dict(os.environ, {"APT_SIGNING_KEY": secret, "APT_SIGNING_PASSPHRASE": ""}):
                    apt.sign(site, fingerprint)
                keyring = self.root / "test.gpg"
                keyring.write_bytes(subprocess.check_output(["gpg", "--export", fingerprint]))
                subprocess.run(["gpgv", "--keyring", str(keyring), str(repo / "dists/jammy/InRelease")], check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                client = self.root / "client"; client.mkdir()
                (client / "lists/partial").mkdir(parents=True)
                (client / "status").touch()
                sources = client / "sources.list"
                sources.write_text(f"deb [arch=amd64 signed-by={repo}/usce-archive-keyring.asc] file:{repo} jammy main\n")
                settings = ["-o", "Dir::Etc::main=-", "-o", "Dir::Etc::parts=-",
                            "-o", "Dir::Etc::sourcelist=" + str(sources), "-o", "Dir::Etc::sourceparts=-",
                            "-o", "Dir::State::lists=" + str(client / "lists"),
                            "-o", "Dir::State::status=" + str(client / "status"),
                            "-o", "Dir::Cache=" + str(client / "cache"),
                            "-o", "APT::Sandbox::User=" + pwd.getpwuid(os.getuid()).pw_name]
                subprocess.run(["apt-get", *settings, "update"], check=True, capture_output=True)
                subprocess.run(["apt-get", *settings, "download", "usce"], cwd=client,
                               check=True, capture_output=True)
                self.assertTrue(list(client.glob("usce_2026.10.1_amd64.deb")))
                # A modified signed Release must be rejected, not silently trusted.
                signed = repo / "dists/jammy/InRelease"
                signed.write_bytes(signed.read_bytes().replace(b"Origin: UltraStar-CE", b"Origin: Tampered"))
                bad = subprocess.run(["gpgv", "--keyring", str(keyring), str(signed)], capture_output=True)
                self.assertNotEqual(bad.returncode, 0)
            finally:
                subprocess.run(["gpgconf", "--kill", "gpg-agent"], capture_output=True)

if __name__ == "__main__":
    unittest.main()
