#!/usr/bin/env python3
"""Validate Toast release metadata without changing any files."""

from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
INFO_PLIST = ROOT / "Toast" / "Resources" / "Info.plist"
LAUNCHER_INFO_PLIST = ROOT / "Toast" / "Resources" / "ToastLauncher-Info.plist"
CANONICAL_CASK = ROOT.parent / "homebrew-toast-tap" / "Casks" / "toast-app.rb"
REFERENCE_CASK = ROOT / "toast-tap" / "Casks" / "toast-app.rb"
APPCAST = ROOT / "web" / "public" / "appcast.xml"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def fail(message: str) -> None:
    raise ValueError(message)


def read_plist() -> tuple[str, str]:
    with INFO_PLIST.open("rb") as handle:
        plist = plistlib.load(handle)
    version = str(plist.get("CFBundleShortVersionString", "")).strip()
    build = str(plist.get("CFBundleVersion", "")).strip()
    if not version or not build:
        fail(f"{INFO_PLIST}: missing CFBundleShortVersionString or CFBundleVersion")
    if LAUNCHER_INFO_PLIST.exists():
        with LAUNCHER_INFO_PLIST.open("rb") as handle:
            launcher = plistlib.load(handle)
        if launcher.get("CFBundleShortVersionString") != version or launcher.get("CFBundleVersion") != build:
            fail(f"{LAUNCHER_INFO_PLIST}: launcher metadata is not aligned with the main app")
    return version, build


def read_cask(path: Path) -> tuple[str, str, str]:
    if not path.exists():
        fail(f"Homebrew cask not found: {path}")
    text = path.read_text(encoding="utf-8")
    version = re.search(r'^\s*version\s+"([^"]+)"', text, re.MULTILINE)
    sha = re.search(r'^\s*sha256\s+"([^"]+)"', text, re.MULTILINE)
    url = re.search(r'^\s*url\s+"([^"]+)"', text, re.MULTILINE)
    if not version or not sha or not url:
        fail(f"{path}: expected version, sha256, and url declarations")
    return version.group(1), sha.group(1), url.group(1)


def validate_cask(path: Path, version: str, expected_sha: str | None = None) -> None:
    cask_version, sha, url = read_cask(path)
    if cask_version != version:
        fail(f"{path}: version {cask_version} does not match {version}")
    if not re.fullmatch(r"[a-f0-9]{64}", sha):
        fail(f"{path}: SHA256 must be 64 lowercase hexadecimal characters")
    expected_urls = {
        f"https://github.com/asitkhanda/toast/releases/download/v{version}/Toast-{version}.dmg",
        "https://github.com/asitkhanda/toast/releases/download/v#{version}/Toast-#{version}.dmg",
    }
    if url not in expected_urls:
        fail(f"{path}: URL does not match the Toast release DMG pattern")
    if expected_sha is not None and sha != expected_sha:
        fail(f"{path}: SHA256 {sha} does not match artifact SHA256 {expected_sha}")


def validate_appcast(version: str, build: str, tag: str | None = None) -> None:
    if not APPCAST.exists():
        fail(f"Appcast not found: {APPCAST}")
    root = ET.parse(APPCAST).getroot()
    items = root.findall("./channel/item")
    matching = [item for item in items if item.findtext(f"{{{SPARKLE_NS}}}shortVersionString") == version]
    if not matching:
        fail(f"{APPCAST}: no item for version {version}")
    item = matching[0]
    if item.findtext(f"{{{SPARKLE_NS}}}version") != build:
        fail(f"{APPCAST}: build does not match {build}")
    enclosure = item.find("enclosure")
    if enclosure is None:
        fail(f"{APPCAST}: version {version} has no enclosure")
    if not enclosure.attrib.get(f"{{{SPARKLE_NS}}}edSignature"):
        fail(f"{APPCAST}: version {version} has no Sparkle EdDSA signature")
    if tag is not None:
        expected = f"https://github.com/asitkhanda/toast/releases/download/{tag}/Toast-{version}.zip"
        if enclosure.attrib.get("url") != expected:
            fail(f"{APPCAST}: enclosure URL does not match {expected}")


def validate_artifacts(directory: Path, version: str, require_windows: bool) -> None:
    dmg = directory / f"Toast-{version}.dmg"
    archive = directory / f"Toast-{version}.zip"
    for artifact in (dmg, archive):
        if not artifact.is_file() or artifact.stat().st_size == 0:
            fail(f"Missing or empty release artifact: {artifact}")
    windows = directory / f"Toast-{version}-win-x64-Setup.exe"
    if require_windows and (not windows.is_file() or windows.stat().st_size == 0):
        fail(f"Missing or empty Windows artifact: {windows}")

    manifest = directory / "SHA256SUMS.txt"
    if manifest.exists():
        entries = {}
        for line in manifest.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) >= 2:
                entries[parts[1].lstrip("* ")] = parts[0]
        for artifact in (dmg, archive, windows if windows.exists() else None):
            if artifact is None:
                continue
            if artifact.name not in entries:
                fail(f"{manifest}: missing checksum for {artifact.name}")
            actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
            if entries[artifact.name] != actual:
                fail(f"{manifest}: checksum mismatch for {artifact.name}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cask", type=Path, action="append", default=[])
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--dmg-sha")
    parser.add_argument("--require-windows", action="store_true")
    parser.add_argument("--tag")
    parser.add_argument("--skip-appcast", action="store_true")
    parser.add_argument("--skip-cask", action="store_true")
    args = parser.parse_args()

    version, build = read_plist()
    if not args.skip_cask:
        for cask in args.cask or [CANONICAL_CASK, REFERENCE_CASK]:
            validate_cask(cask, version, args.dmg_sha)
    if not args.skip_appcast:
        validate_appcast(version, build, args.tag)
    if args.artifacts:
        validate_artifacts(args.artifacts, version, args.require_windows)
    print(f"Release metadata valid: Toast {version} (build {build})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"Release validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
