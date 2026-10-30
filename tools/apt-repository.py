"""Publish checked release DEBs as a signed, static Ubuntu APT repository."""
import argparse
import datetime
import email.utils
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

VERSION = re.compile(r"[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+")
REPOSITORY = "UltraStar-CE/USCE"

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def collect(destination, required_tag=None):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    pages = json.loads(subprocess.check_output([
        "gh", "api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases"], text=True))
    candidates = []
    for release in [item for page in pages for item in page]:
        tag = release["tag_name"]
        version = tag.removeprefix("v")
        if release["draft"] or release["prerelease"] or not VERSION.fullmatch(version):
            continue
        assets = {a["name"]: a for a in release["assets"]}
        name = f"USCE-linux-deb-{version}.deb"
        if name not in assets:
            if tag == required_tag:
                raise ValueError("Published release has no Ubuntu DEB; finish the package release first")
            continue
        candidates.append((tuple(map(int, version.split("."))), tag, version, name, assets))
    candidates.sort(reverse=True)
    candidates = candidates[:12]
    if not candidates or (required_tag and required_tag not in [c[1] for c in candidates]):
        raise ValueError("No matching published stable DEB release")
    total_size = 0
    for _, tag, version, name, assets in candidates:
        if total_size + assets[name]["size"] > 800 * 1024 * 1024:
            break
        total_size += assets[name]["size"]
        def download(asset_name):
            asset = assets[asset_name]
            if asset["size"] > 500 * 1024 * 1024:
                raise ValueError("Unexpectedly large release asset")
            return subprocess.check_output(["gh", "api", "-H", "Accept: application/octet-stream",
                f"repos/{REPOSITORY}/releases/assets/{int(asset['id'])}"])
        sums = download("SHA256SUMS").decode("ascii")
        matches = re.findall(r"^([a-fA-F0-9]{64})  " + re.escape(name) + r"$", sums, re.M)
        data = download(name)
        if len(matches) != 1 or hashlib.sha256(data).hexdigest() != matches[0].lower():
            raise ValueError("Release DEB checksum mismatch: " + tag)
        (destination / f"usce_{version}_amd64.deb").write_bytes(data)

def build(packages, destination):
    packages, destination = Path(packages), Path(destination)
    if destination.exists():
        raise ValueError("Repository output must not exist")
    files = sorted(packages.glob("*.deb"))
    if not files:
        raise ValueError("No DEB packages")
    seen = set()
    for package in files:
        if package.is_symlink():
            raise ValueError("Package symlinks are unsupported")
        values = [subprocess.check_output(["dpkg-deb", "-f", str(package), key], text=True).strip()
                  for key in ["Package", "Version", "Architecture"]]
        name, version, arch = values
        if name != "usce" or arch != "amd64" or not VERSION.fullmatch(version):
            raise ValueError("Expected a stable USCE Ubuntu amd64 package")
        if (version, arch) in seen:
            raise ValueError("Duplicate package version")
        seen.add((version, arch))
    pool = destination / "apt/pool/main/u/usce"
    pool.mkdir(parents=True)
    for package in files:
        version = subprocess.check_output(["dpkg-deb", "-f", str(package), "Version"], text=True).strip()
        shutil.copyfile(package, pool / f"usce_{version}_amd64.deb")
    apt = destination / "apt"
    index = apt / "dists/jammy/main/binary-amd64"
    index.mkdir(parents=True)
    data = subprocess.check_output(["dpkg-scanpackages", "--multiversion", "pool", "/dev/null"], cwd=apt)
    (index / "Packages").write_bytes(data)
    (index / "Packages.gz").write_bytes(gzip.compress(data, mtime=0))
    options = {"Origin": "UltraStar-CE", "Label": "USCE", "Suite": "jammy", "Codename": "jammy",
               "Architectures": "amd64", "Components": "main"}
    command = ["apt-ftparchive"]
    for key, value in options.items():
        command += ["-o", f"APT::FTPArchive::Release::{key}={value}"]
    release = subprocess.check_output(command + ["release", "dists/jammy"], cwd=apt)
    expires = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=180)
    release = ("Valid-Until: " + email.utils.format_datetime(expires, usegmt=True) + "\n").encode() + release
    (apt / "dists/jammy/Release").write_bytes(release)
    (destination / ".nojekyll").touch()
    (destination / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>USCE packages</title>'
        '<h1>USCE packages</h1><p>Ubuntu 22.04 (jammy), amd64.</p>'
        '<p><a href="https://github.com/UltraStar-CE/USCE/blob/main/APT.md">Installation instructions</a></p>')
    return apt

def sign(destination, fingerprint):
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", fingerprint):
        raise ValueError("Set the full OpenPGP primary-key fingerprint")
    fingerprint = fingerprint.upper()
    apt = Path(destination) / "apt"
    release = apt / "dists/jammy/Release"
    if not release.is_file():
        raise ValueError("Missing repository metadata")
    # GNUPGHOME belongs to the isolated signing job. Never use a developer's keyring.
    if not os.environ.get("GNUPGHOME"):
        raise ValueError("Use an isolated GNUPGHOME")
    secret = os.environ["APT_SIGNING_KEY"].encode()
    run(["gpg", "--batch", "--import"], input=secret, stdout=subprocess.DEVNULL)
    listing = subprocess.check_output(["gpg", "--batch", "--with-colons", "--list-secret-keys"], text=True)
    primary = None
    for line in listing.splitlines():
        fields = line.split(":")
        if fields[0] == "sec": primary = "pending"
        elif fields[0] == "fpr" and primary == "pending":
            primary = fields[9]
            if primary != fingerprint:
                raise ValueError("Signing key does not match the configured fingerprint")
    if fingerprint not in listing:
        raise ValueError("Configured secret signing key is absent")
    common = ["gpg", "--batch", "--yes", "--local-user", fingerprint, "--digest-algo", "SHA256",
              "--pinentry-mode", "loopback", "--passphrase-fd", "0"]
    password = os.environ.get("APT_SIGNING_PASSPHRASE", "").encode() + b"\n"
    run(common + ["--output", str(release.with_name("InRelease")), "--clearsign", str(release)], input=password)
    run(common + ["--armor", "--output", str(release.with_name("Release.gpg")), "--detach-sign", str(release)], input=password)
    public = subprocess.check_output(["gpg", "--batch", "--armor", "--export", fingerprint])
    (apt / "usce-archive-keyring.asc").write_bytes(public)
    (apt / "fingerprint.txt").write_text(fingerprint + "\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("collect"); p.add_argument("output"); p.add_argument("--required-tag")
    p = sub.add_parser("build"); p.add_argument("packages"); p.add_argument("output")
    p = sub.add_parser("sign"); p.add_argument("output"); p.add_argument("fingerprint")
    args = parser.parse_args()
    if args.command == "collect": collect(args.output, args.required_tag)
    elif args.command == "build": build(args.packages, args.output)
    else: sign(args.output, args.fingerprint)
