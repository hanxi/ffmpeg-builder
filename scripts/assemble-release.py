#!/usr/bin/env python3
"""Assemble per-target FFmpeg assets into one immutable release manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--channel", choices=("stable", "dev"), required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--configure-args", nargs="*", default=[])
    args = parser.parse_args()
    assets = []
    for archive in sorted(args.directory.glob("ffmpeg-*.tar.gz")) + sorted(args.directory.glob("ffmpeg-*.zip")):
        name = archive.name
        stem = name.removeprefix("ffmpeg-")
        suffix = ".tar.gz" if name.endswith(".tar.gz") else ".zip"
        target = stem[: -len(suffix)].removeprefix(f"{args.version}-")
        if target not in {
            "linux-x86_64", "linux-arm64", "linux-armv7", "windows-x86_64",
            "macos-arm64", "macos-x86_64", "android-arm64-v8a", "android-armeabi-v7a",
            "android-x86_64", "ios-arm64",
        }:
            raise SystemExit(f"unknown asset target in {name}")
        platform_name, architecture = target.rsplit("-", 1)
        if target == "android-arm64-v8a":
            platform_name, architecture = "android", "arm64-v8a"
        elif target == "android-armeabi-v7a":
            platform_name, architecture = "android", "armeabi-v7a"
        elif target == "android-x86_64":
            platform_name, architecture = "android", "x86_64"
        assets.append({
            "name": name,
            "target": target,
            "platform": platform_name,
            "architecture": architecture,
            "kind": "static-library" if target == "ios-arm64" else "executable",
            "size": archive.stat().st_size,
            "sha256": digest(archive),
        })
    if not assets:
        raise SystemExit("no release assets found")
    manifest = {
        "schema": 1,
        "channel": args.channel,
        "release_tag": args.release_tag,
        "ffmpeg_version": args.version,
        "source_commit": args.source_commit,
        "license": "GPL-3.0-or-later",
        "configure_args": args.configure_args,
        "assets": assets,
    }
    manifest_path = args.directory / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    files = sorted(path for path in args.directory.iterdir() if path.is_file() and path.name != "checksums.txt")
    (args.directory / "checksums.txt").write_text(
        "".join(f"{digest(path)}  {path.name}\n" for path in files), encoding="utf-8"
    )
    print(json.dumps({"manifest": str(manifest_path), "assets": len(assets)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
