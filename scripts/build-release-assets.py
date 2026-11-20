#!/usr/bin/env python3
"""Package and validate one FFmpeg release asset.

The platform toolchains live in the release workflow. This script keeps the
archive format, naming, metadata and digest rules in one place so every
runner produces the same release contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform as host_platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path


FFMPEG_VERSION = os.environ.get("FFMPEG_VERSION", "8.0.1")
SOURCE_COMMIT = os.environ.get("FFMPEG_SOURCE_COMMIT", "")
LICENSE = "GPL-3.0-or-later"

TARGETS = {
    "linux-x86_64": ("linux", "x86_64", "executable", ".tar.gz"),
    "linux-arm64": ("linux", "arm64", "executable", ".tar.gz"),
    "linux-armv7": ("linux", "armv7", "executable", ".tar.gz"),
    "windows-x86_64": ("windows", "x86_64", "executable", ".zip"),
    "macos-arm64": ("macos", "arm64", "executable", ".tar.gz"),
    "macos-x86_64": ("macos", "x86_64", "executable", ".tar.gz"),
    "android-arm64-v8a": ("android", "arm64-v8a", "executable", ".tar.gz"),
    "android-armeabi-v7a": ("android", "armeabi-v7a", "executable", ".tar.gz"),
    "android-x86_64": ("android", "x86_64", "executable", ".tar.gz"),
    "ios-arm64": ("ios", "arm64", "static-library", ".tar.gz"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_output(path: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            [str(path), *args], check=True, capture_output=True, text=True
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise ValueError(f"cannot execute {path}: {error}") from error
    return result.stdout + result.stderr


def check_executable(path: Path, expected_version: str, expected_architecture: str, run_version: bool) -> None:
    if not path.is_file() or not (path.stat().st_mode & stat.S_IXUSR):
        raise ValueError(f"{path} must be a regular executable file")
    file_info = ""
    if shutil.which("file"):
        file_info = subprocess.run(["file", str(path)], capture_output=True, text=True, check=False).stdout.lower()
    architecture_tokens = {
        "x86_64": ("x86-64", "x86_64", "amd64"),
        "arm64": ("aarch64", "arm64"),
        "armv7": ("arm", "armv7"),
        "arm64-v8a": ("aarch64", "arm64"),
        "armeabi-v7a": ("arm", "armv7"),
    }.get(expected_architecture, ())
    if architecture_tokens and any(marker in file_info for marker in ("elf", "pe32", "mach-o")) and not any(token in file_info for token in architecture_tokens):
        raise ValueError(f"{path} has an unexpected architecture: {file_info.strip()}")
    if run_version:
        version = command_output(path, "-version").splitlines()[0]
        if not re.search(rf"\bversion (?:n)?{re.escape(expected_version)}(?:[ -]|$)", version):
            raise ValueError(f"{path} reports an unexpected version: {version}")


def check_static_library(path: Path, expected_arch: str) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"{path} must be a non-empty static library or framework")
    if path.suffix == ".a" and path.read_bytes()[:8] != b"!<arch>\n":
        raise ValueError(f"{path} is not an ar archive")
    if shutil.which("lipo"):
        output = command_output(Path("lipo"), "-info", str(path))
        if expected_arch == "arm64" and "arm64" not in output:
            raise ValueError(f"{path} does not contain arm64: {output.strip()}")


def archive_name(target: str, version: str) -> str:
    _, _, _, suffix = TARGETS[target]
    return f"ffmpeg-{version}-{target}{suffix}"


def make_archive(target: str, version: str, source_commit: str, ffmpeg: Path | None, ffprobe: Path | None, framework: Path | None, output: Path) -> list[dict[str, object]]:
    platform_name, architecture, kind, _ = TARGETS[target]
    output.mkdir(parents=True, exist_ok=True)
    archive = output / archive_name(target, version)
    with tempfile.TemporaryDirectory(prefix="ffmpeg-release-") as temporary:
        root = Path(temporary) / f"ffmpeg-{version}-{target}"
        root.mkdir()
        if kind == "executable":
            if ffmpeg is None or ffprobe is None:
                raise ValueError("executable targets require --ffmpeg and --ffprobe")
            extension = ".exe" if platform_name == "windows" else ""
            check_executable(ffmpeg, version, architecture, target == "linux-x86_64")
            check_executable(ffprobe, version, architecture, target == "linux-x86_64")
            shutil.copy2(ffmpeg, root / f"ffmpeg{extension}")
            shutil.copy2(ffprobe, root / f"ffprobe{extension}")
        else:
            if framework is None:
                raise ValueError("ios-arm64 requires --framework")
            if framework.is_dir():
                libraries = sorted(framework.glob("*.a"))
                if not libraries:
                    raise ValueError(f"{framework} must contain at least one static library")
                destination = root / framework.name
                shutil.copytree(framework, destination)
                for library in libraries:
                    check_static_library(library, architecture)
            else:
                check_static_library(framework, architecture)
                shutil.copy2(framework, root / framework.name)

        metadata = {
            "target": target,
            "platform": platform_name,
            "architecture": architecture,
            "kind": kind,
            "ffmpeg_version": version,
            "source_commit": source_commit,
            "license": LICENSE,
        }
        (root / "asset.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        if archive.suffix == ".zip":
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as handle:
                for path in sorted(root.rglob("*")):
                    if path.is_file():
                        handle.write(path, path.relative_to(Path(temporary)).as_posix())
        else:
            with tarfile.open(archive, "w:gz") as handle:
                handle.add(root, arcname=root.name)

    return [{
        "name": archive.name,
        "target": target,
        "platform": platform_name,
        "architecture": architecture,
        "kind": kind,
        "size": archive.stat().st_size,
        "sha256": sha256(archive),
    }]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=sorted(TARGETS))
    parser.add_argument("--version", default=FFMPEG_VERSION)
    parser.add_argument("--source-commit", default=SOURCE_COMMIT)
    parser.add_argument("--release-tag", default=os.environ.get("RELEASE_TAG", ""))
    parser.add_argument("--channel", choices=("stable", "dev"), default=os.environ.get("RELEASE_CHANNEL", "stable"))
    parser.add_argument("--ffmpeg", type=Path)
    parser.add_argument("--ffprobe", type=Path)
    parser.add_argument("--framework", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, help="write or merge the release manifest")
    parser.add_argument("--configure-args", nargs="*", default=[])
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("--version must be a semantic FFmpeg version")
    if not re.fullmatch(r"[a-f0-9]{40}", args.source_commit):
        parser.error("--source-commit must be a 40-character source SHA")
    if args.channel == "dev" and args.release_tag != "dev":
        parser.error("dev assets must use the dev release tag")
    if args.channel == "stable" and not args.release_tag:
        parser.error("stable assets require the concrete release tag")

    assets = make_archive(args.target, args.version, args.source_commit, args.ffmpeg, args.ffprobe, args.framework, args.output_dir)
    manifest_path = args.manifest or args.output_dir / "manifest.json"
    existing = {}
    if manifest_path.exists():
        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
    existing.update({
        "schema": 1,
        "channel": args.channel,
        "release_tag": args.release_tag,
        "ffmpeg_version": args.version,
        "source_commit": args.source_commit,
        "license": LICENSE,
        "configure_args": args.configure_args,
        "assets": sorted([*existing.get("assets", []), *assets], key=lambda item: item["target"]),
        "build": {
            "runner": host_platform.platform(),
            "python": sys.version.split()[0],
        },
    })
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
    checksums = manifest_path.parent / "checksums.txt"
    files = sorted(path for path in manifest_path.parent.iterdir() if path.is_file() and path.name != checksums.name)
    checksums.write_text("".join(f"{sha256(path)}  {path.name}\n" for path in files), encoding="utf-8")
    print(json.dumps({"target": args.target, "asset": assets[0], "manifest": str(manifest_path)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
