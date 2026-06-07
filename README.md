# FFmpeg Builder

一个轻量级的 Docker 镜像构建器，用于创建包含静态编译的 ffmpeg 和 ffprobe 可执行文件的最小镜像。仅保留音频相关能力，内置 chromaprint 音频指纹支持。

## 特性

- 基于 Alpine Linux 3.20 构建
- 静态编译的 ffmpeg + ffprobe 可执行文件
- 最小化运行时镜像（基于 scratch）
- 仅包含音频编解码器，体积极小
- 内置 chromaprint muxer，支持 AcoustID 音频指纹识别（无需独立 fpcalc）

## 支持的格式

| 功能 | 格式 |
|------|------|
| 解码 | MP3, AAC, FLAC, Vorbis, Opus, WAV/PCM, ALAC, APE, WavPack, DSD |
| 编码 | MP3 (LAME), AAC, FLAC, Vorbis, Opus, WAV/PCM |
| 容器 | MP3, FLAC, OGG, WAV, M4A (ADTS/iPod), MKA, DSF, Chromaprint |

## 快速开始

### 构建镜像

```bash
docker build -t hanxi/ffmpeg .
```

### 在其他 Dockerfile 中使用

```dockerfile
COPY --from=hanxi/ffmpeg /ffmpeg /bin/ffmpeg
COPY --from=hanxi/ffmpeg /ffprobe /bin/ffprobe
```

### 运行容器

```bash
# ffmpeg 转码
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.flac -c:a libmp3lame -q:a 2 /music/output.mp3

# ffprobe 探测
docker run --rm -v /music:/music --entrypoint /ffprobe hanxi/ffmpeg \
  -show_format -show_streams /music/input.mp3

# 提取音频指纹（chromaprint）
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.mp3 -f chromaprint -fp_format compressed -
```

## 转码示例

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
```

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。
