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

## License

This project uses the MIT license; see [LICENSE](LICENSE).
