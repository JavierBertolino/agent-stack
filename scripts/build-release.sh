#!/usr/bin/env python3
"""build-release.sh — build the versioned public release artifacts.

Reads VERSION, packs the distributable kit (scripts, .agent-stack, VERSION
plus public root files) into dist/astack.tar.gz, and writes SHA-256
checksums plus a copy of the public install.sh for the GitHub Release:

  dist/astack.tar.gz
  dist/astack.tar.gz.sha256
  dist/checksums.txt
  dist/install.sh

Usage:
  scripts/build-release.sh [--kit-root PATH] [--dist DIR] [--skip-smoke]

--skip-smoke skips the clean-install smoke test (extract, sh -n, init a
scratch project, doctor). Release CI always runs the smoke test.
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT_FILES = ["LICENSE", "README.md", "CHANGELOG.md"]
KIT_DIRS = ["scripts", ".agent-stack"]
KIT_FILES = ["VERSION"]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build(kit, dist, skip_smoke):
    version = (kit / "VERSION").read_text().split()[0]
    dist.mkdir(parents=True, exist_ok=True)

    tarball = dist / "astack.tar.gz"
    with tarfile.open(tarball, "w:gz", format=tarfile.PAX_FORMAT) as archive:
        for name in KIT_DIRS + KIT_FILES:
            source = kit / name
            if not source.exists():
                raise SystemExit("build error: missing %s" % source)
            archive.add(source, arcname=name)
        for name in ROOT_FILES:
            source = kit / name
            if source.exists():
                archive.add(source, arcname=name)

    digest = sha256(tarball)
    (dist / "astack.tar.gz.sha256").write_text("%s  astack.tar.gz\n" % digest)
    shutil.copy(kit / "install.sh", dist / "install.sh")
    (dist / "VERSION").write_text(version + "\n")

    checksums = dist / "checksums.txt"
    lines = ["%s  astack.tar.gz" % digest,
             "%s  install.sh" % sha256(dist / "install.sh")]
    checksums.write_text("\n".join(lines) + "\n")

    print("build-release: Agent Stack v%s" % version)
    for artifact in ["astack.tar.gz", "astack.tar.gz.sha256",
                     "checksums.txt", "install.sh"]:
        print("  dist/%s" % artifact)
    return version


def smoke(kit, dist, version):
    tmp = Path(tempfile.mkdtemp(prefix="astack-release-smoke."))
    try:
        tarball = dist / "astack.tar.gz"
        with tarfile.open(tarball, "r:gz") as archive:
            archive.extractall(tmp / "kit")

        extracted = tmp / "kit"
        for script in ["setup-agent-stack.sh", "doctor.sh",
                       "upgrade-agent-stack.sh", "update-agent-stack.sh",
                       "astack"]:
            subprocess.run(["sh", "-n", str(extracted / "scripts" / script)],
                           check=True)

        prefix = tmp / "prefix"
        project = tmp / "project"
        project.mkdir()
        env = dict(__import__("os").environ)
        env["ASTACK_RELEASE_BASE"] = str(dist)
        subprocess.run(["sh", str(extracted / "install.sh"),
                        "--global", "--prefix=%s" % prefix],
                       check=True, env=env, capture_output=True, text=True)
        dispatcher = prefix / "bin" / "astack"
        if not dispatcher.is_file():
            raise SystemExit("smoke error: bin/astack missing")
        out = subprocess.run([str(dispatcher), "--version"],
                             capture_output=True, text=True, check=True)
        if out.stdout.strip() != version:
            raise SystemExit("smoke error: version mismatch %r != %r"
                             % (out.stdout.strip(), version))
        subprocess.run([str(dispatcher), "init", "--platforms", "opencode",
                        "--mcp", "none"],
                       cwd=str(project), check=True,
                       capture_output=True, text=True)
        subprocess.run([str(dispatcher), "check"], cwd=str(project),
                       check=True, capture_output=True, text=True)
        subprocess.run([str(dispatcher), "doctor"], cwd=str(project),
                       check=True, capture_output=True, text=True)
        print("build-release: smoke test passed (install, init, check, doctor)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Build release artifacts")
    parser.add_argument("--kit-root", default=".")
    parser.add_argument("--dist", default="dist")
    parser.add_argument("--skip-smoke", action="store_true")
    args = parser.parse_args()

    kit = Path(args.kit_root)
    dist = Path(args.dist)
    version = build(kit, dist, args.skip_smoke)
    if not args.skip_smoke:
        smoke(kit, dist, version)


if __name__ == "__main__":
    main()
