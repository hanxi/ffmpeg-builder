# Development lessons

[中文](LESSONS.md)

## BUILD-001: Validate minimal tools' input capabilities using built artifacts

- Scope: static FFmpeg/FFprobe with `--disable-everything` and Songloft HLS inputs; [songloft-org/songloft#541 feedback](https://github.com/songloft-org/songloft/issues/541#issuecomment-6516328627). Builder baseline: `58891be59f4141df33b88c400531d42aa23b9d3d`; parent baseline: `dc762612f5deb0df966b4e273d3d9623d897c4f7`.
- Failure evidence: the old configuration enabled the HLS muxer without the HLS demuxer or crypto protocol. Both were absent in existing Docker tools. System tools could probe the actual source, while the original backend with old tools returned “无法探测上游媒体” (unable to probe upstream media). New artifact tests passed direct TS with the old image but failed plain HLS probing. Logs: `/tmp/songloft-541-builder-before-final.log`, `/tmp/songloft-541-service-real-before.log`.
- Rule and fix: HLS output does not imply HLS input. Explicitly enable the `hls` demuxer and `crypto` protocol. System tools generate fixtures and independently inspect output; before pushing, use built ffprobe/ffmpeg to exercise TS, master→media→segments, and AES-128→key fetching. Verify identical SHA-256 hashes for every video packet.
- Done right: all three artifact tests passed on Linux amd64 with static FFmpeg 8.0.1, producing AAC-LC stereo at 48 kHz; log: `/tmp/songloft-541-builder-after.log`. System FFmpeg 5.1.7 fixture tests, Ruff, and actionlint v1.7.12 passed. Slow upstream downloads required an APK mirror and cached upstream archives for local validation; only download locations changed, preserving compiler options. Archive checks/hashes: `/tmp/songloft-541-source-hashes.txt`; final build log: `/tmp/songloft-541-ffmpeg-build-final.log`.
- Backend validation: an isolated Go overlay substituted the new tools in test services without changing business source. All focused HLS tests passed. The first actual source created a session in about seven seconds; HTTP playlists, segments, Range, deletion, and reclamation passed, producing H.264 1920×1080 and AAC-LC stereo at 48 kHz. Logs: `/tmp/songloft-541-go-new-tools.log`, `/tmp/songloft-541-actual-http.log`; final worktrees and commands: `/tmp/songloft-541-verification.json`. The third source reset connections from the local network; the second source with an expiring signature was not accepted as a validation sample.
- Release boundary: after this repository is fixed, publish its tool image and let the Songloft build mirror it before recreating containers. Songloft's binary updater does not replace ffmpeg/ffprobe; the application version alone does not prove tool capabilities.
- Not run during local validation: ARM artifact execution, remote CI, and iPhone Safari. amd64 and backend checks do not replace those validations.
- Seen 1× (2026-10-30). Status: this fix; image builds, parent gitlink synchronization, and device acceptance must be checked against subsequent delivery records for the corresponding commits.

## BUILD-002: Source downloads need explicit, bounded retries for connection resets

- Scope: source downloads in multi-architecture image builds; [CI for dd9a8df](https://github.com/hanxi/ffmpeg-builder/actions/runs/41065204390).
- Failure evidence: the amd64 build and all three HLS artifact tests passed, but the arm/v7 FFmpeg source download encountered a connection reset. `curl` exited 35 and stopped the entire multi-architecture build. Log: `/tmp/songloft-541-ffmpeg-ci-failed.log`. This is a download failure, not a media regression; an unpublished image is not an available package.
- Rule and fix: all source downloads explicitly use `--retry 5 --retry-all-errors` to cover TLS/connection resets, with connection, transfer, and retry time limits. Preserve `--fail`, TLS verification, and extraction only after successful download; do not ignore errors to continue building.
- Done right: a local TLS server interrupted the first connection. The old command exited 35 after one connection; new options extracted from the Dockerfile retried successfully, with two connections and complete file content. Log: `/tmp/songloft-541-curl-retry-check.log`; verify actual multi-architecture publication against CI for the fix commit.
- Seen 1× (2026-10-30). Status: build resilience fix; the same incident does not increment BUILD-001.

## BUILD-003: Resolve the Release identity before downloading Bundle assets

- Scope: multi-platform FFmpeg release assets and Bundle resolution, including the new `release-assets.yml`, `scripts/build-release-assets.py`, and the parent resolver.
- Rule: resolve a concrete Release tag for the selected channel first, then validate the manifest tag, platform, ABI, size, and SHA-256. Save the resolution and reuse it across the whole matrix. Jobs must not read a rolling `latest` URL directly.
- Correct example: `ffmpeg-resolution.json` records `release_tag`, `source_commit`, `manifest_sha256`, and each asset digest. Downloads are checked again and missing or replaced assets stop the build.
- Seen 1× (2026-11-20). Status: local implementation; remote multi-platform builds and device installation remain for release-pipeline acceptance.

### BUILD-004: Link macOS release tools only to system dynamic libraries

- Evidence: the Lynx Intel macOS Bundle in Songloft CI run `44748954168` rejected FFmpeg's `libX11.6.dylib` dependency. FFmpeg detected an extra library on the build runner that was absent from the installer.
- Rule: disable macOS FFmpeg autodetection, explicitly enable system TLS and zlib, and check the executables with `otool -L` before publishing. Accept only system paths.
- Seen 1× (2026-11-20).
