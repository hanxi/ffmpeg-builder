# FFmpeg Builder

A lightweight Docker builder for minimal images containing static ffmpeg and ffprobe executables. Includes audio processing, video decoding and HLS output (H.264/AAC), and Chromaprint audio fingerprints.

[中文](README.md)

## Features

- Built on Alpine Linux 3.20
- Static ffmpeg and ffprobe executables
- Source downloads retry up to five times, including TLS/connection resets, with connection, transfer, and retry time limits
- Minimal scratch runtime image
- Audio codecs, common video containers, and libx264 HLS output
- Plain HLS input and AES-128 encrypted segments (`hls` demuxer and `crypto` protocol)
- Audio filters: aresample, loudnorm (EBU R128), and atempo (pitch-preserving speed changes, 0.5–2.0 per filter)
- Chromaprint muxer for AcoustID fingerprints without a separate fpcalc
- Release assets for Linux, Windows, macOS, Android, and iOS with ABI-specific names and SHA-256 digests

## Supported formats

| Capability | Formats |
|---|---|
| Audio decoding | MP3, MP2, AAC, FLAC, Vorbis, Opus, WAV/PCM, ALAC, APE, WavPack, WMA, AC3/EAC3, DTS, Cook (RealAudio) |
| Audio encoding | MP3 (LAME), AAC, FLAC, Vorbis, Opus, WAV/PCM |
| Video decoding | H.264, HEVC, VP8/VP9, MPEG-1/2, MPEG-4/DivX, MSMPEG4, WMV1/2/3, VC-1, FLV1, H.263, RealVideo (RV10-40), Theora |
| Video encoding | H.264 (libx264) |
| Input containers | MP3, FLAC, OGG, WAV, MP4/MOV/M4V/3GP, MKV/WebM, ASF/WMA/WMV, APE, WV, MPEG-PS (MPG), MPEG-TS, HLS, AVI, FLV, RM/RMVB |
| Output containers | MP3, FLAC, OGG, WAV, M4A (ADTS/iPod), MKA, HLS (m3u8+TS), MPEG-TS, Chromaprint |

> Static libx264 linking requires `--enable-gpl`; the distributed binaries are GPL licensed.

## Quick start

### Build the image

```bash
docker build -t hanxi/ffmpeg .
```

### Use in another Dockerfile

```dockerfile
COPY --from=hanxi/ffmpeg /ffmpeg /bin/ffmpeg
COPY --from=hanxi/ffmpeg /ffprobe /bin/ffprobe
```

### Run containers

```bash
# Transcode audio
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.flac -c:a libmp3lame -q:a 2 /music/output.mp3

# Probe media
docker run --rm -v /music:/music --entrypoint /ffprobe hanxi/ffmpeg \
  -show_format -show_streams /music/input.mp3

# Extract a Chromaprint fingerprint
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.mp3 -f chromaprint -fp_format compressed -
```

## Transcoding examples

```bash
# FLAC -> MP3
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.flac -c:a libmp3lame -q:a 2 /music/output.mp3

# MP3 -> FLAC
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.mp3 -c:a flac /music/output.flac

# Any -> OGG/Opus
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.wav -c:a libopus -b:a 128k /music/output.opus

# Any -> AAC/M4A
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.flac -c:a aac -b:a 256k /music/output.m4a

# Pitch-preserving speed change (chain filters outside 0.5–2.0)
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.mp3 -map 0:a:0 -vn -codec:a libmp3lame -b:a 320k \
  -af atempo=1.5 -write_xing 0 -f mp3 /music/output_1.5x.mp3
```

## Validate built binaries

On a Linux host with Docker, Python 3, and a full FFmpeg installation including libx264:

```bash
docker build -t ffmpeg-hls-test:local .
python3 tests/hls_input.py --image ffmpeg-hls-test:local
```

System FFmpeg generates six seconds of synthetic H.264 + MP2 media and independently inspects output codecs. The image's ffprobe/ffmpeg perform the actual probing and transcoding. A local HTTP server serves direct TS, master→media→TS playlists, and AES-128 HLS with key fetching. Tests check AAC-LC stereo at 48 kHz, HLS output, and identical SHA-256 hashes for every H.264 packet. CI builds and runs the amd64 image before pushing multiple architectures; ARM execution requires separate validation.

Songloft's binary updater does not replace ffmpeg/ffprobe inside a container. After fixing this tool image, wait for the Songloft build to mirror it, then pull the new image and recreate the container. Updating only the Songloft executable cannot add capabilities to old tools.

## Multi-platform release assets

`release-assets.yml` packages ten targets. Pushes to `main` that change `Dockerfile`, `scripts/**`, `tests/**`, or this workflow update `dev`. Pushing a `vX.Y.Z` tag publishes the corresponding stable assets. To run **Actions → Release FFmpeg assets** manually, select `channel=dev` and `release_tag=dev` for a development build, or `channel=stable` and a concrete version tag for stable. Each release contains `manifest.json`, `checksums.txt`, and platform archives. Each archive's `asset.json` records its target, source commit, and GPL license.

The separate `build-ffprobe.yml` workflow builds Docker images. It handles pushes and pull requests targeting `main` that change `Dockerfile`, `tests/**`, or that workflow. Documentation-only changes trigger neither workflow. Existing Releases receive replacements under the same asset names. Verify their digests and manifest when checking a build.

[Latest stable](https://github.com/hanxi/ffmpeg-builder/releases/latest) · [dev](https://github.com/hanxi/ffmpeg-builder/releases/tag/dev) · [Package inventory](https://songloft.hanxi.cc/en/release-packages)

Build one asset locally with the platform toolchain:

```bash
FFMPEG_SOURCE_DIR=/path/to/ffmpeg-8.0.1 \
  scripts/build-native-release.sh linux-x86_64 /tmp/ffmpeg-build
source_commit=894da5ca7d742e4429ffb2af534fcda0103ef593
python3 scripts/build-release-assets.py \
  --target linux-x86_64 --version 8.0.1 --release-tag dev --channel dev \
  --source-commit "$source_commit" \
  --ffmpeg /tmp/ffmpeg-build/bin/ffmpeg \
  --ffprobe /tmp/ffmpeg-build/bin/ffprobe --output-dir release-assets
```

Bundle builds resolve the `dev` or stable Release first, then validate its tag, platform, ABI, size, and SHA-256 digest from the manifest. The resolved Release tag, FFmpeg source commit, and asset digests are saved with the build. Every matrix job reuses that result instead of downloading an unversioned `latest` file.

The iOS arm64 asset contains `framework/libsongloft_ffmpeg.a`, the public headers, and `link-flags.txt` for static linking into gomobile. Android ships position independent executables for the APK's `lib/<ABI>/` directory. The build checks the ELF interpreter, system dependencies, and 16 KiB alignment. The Bundle targets include MP3, Vorbis, H.264, and Chromaprint support.

## License

This project uses the MIT license; see [LICENSE](LICENSE).
