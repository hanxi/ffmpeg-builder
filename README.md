# FFmpeg Builder

一个轻量级的 Docker 镜像构建器，用于创建包含静态编译的 ffmpeg 和 ffprobe 可执行文件的最小镜像。保留音频能力 + 视频解码转 HLS（H.264/AAC）能力，内置 chromaprint 音频指纹支持。

[English](README.en.md)

## 特性

- 基于 Alpine Linux 3.20 构建
- 静态编译的 ffmpeg + ffprobe 可执行文件
- 最小化运行时镜像（基于 scratch）
- 音频编解码 + 常见视频容器解码、libx264 编码输出 HLS
- 普通 HLS 输入与 AES-128 加密分片读取（`hls` demuxer + `crypto` 协议）
- 音频滤镜：aresample（重采样）、loudnorm（EBU R128 音量均衡）、atempo（变速不变调，0.5–2.0 倍速播放）
- 内置 chromaprint muxer，支持 AcoustID 音频指纹识别（无需独立 fpcalc）

## 支持的格式

| 功能 | 格式 |
|------|------|
| 音频解码 | MP3, MP2, AAC, FLAC, Vorbis, Opus, WAV/PCM, ALAC, APE, WavPack, WMA, AC3/EAC3, DTS, Cook (RealAudio) |
| 音频编码 | MP3 (LAME), AAC, FLAC, Vorbis, Opus, WAV/PCM |
| 视频解码 | H.264, HEVC, VP8/VP9, MPEG-1/2, MPEG-4/DivX, MSMPEG4, WMV1/2/3, VC-1, FLV1, H.263, RealVideo (RV10-40), Theora |
| 视频编码 | H.264 (libx264) |
| 容器（读） | MP3, FLAC, OGG, WAV, MP4/MOV/M4V/3GP, MKV/WebM, ASF/WMA/WMV, APE, WV, MPEG-PS (MPG), MPEG-TS, HLS, AVI, FLV, RM/RMVB |
| 容器（写） | MP3, FLAC, OGG, WAV, M4A (ADTS/iPod), MKA, HLS (m3u8+TS), MPEG-TS, Chromaprint |

> 注意：因静态链接 libx264，构建产物以 `--enable-gpl` 编译，二进制遵循 GPL 许可分发。

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

# 变速不变调（atempo，0.5–2.0，超出需链式拼接）
docker run --rm -v /music:/music hanxi/ffmpeg \
  -i /music/input.mp3 -map 0:a:0 -vn -codec:a libmp3lame -b:a 320k \
  -af atempo=1.5 -write_xing 0 -f mp3 /music/output_1.5x.mp3
```

## 构建产物验证

在 Linux 主机安装 Docker、Python 3 和完整版 FFmpeg（含 libx264），构建后执行：

```bash
docker build -t ffmpeg-hls-test:local .
python3 tests/hls_input.py --image ffmpeg-hls-test:local
```

系统 FFmpeg 只生成 6 秒合成 H.264 + MP2 夹具，并独立检查输出编码；实际探测和转码使用镜像内的 ffprobe/ffmpeg。测试通过本机 HTTP 服务覆盖直接 TS、主列表→子列表→TS、AES-128 HLS→密钥读取，检查 AAC-LC 双声道 48 kHz、HLS 输出和 H.264 逐包 SHA-256 不变。CI 在推送多架构镜像前先构建、运行 amd64 产物；ARM 运行验证另行执行。

Songloft 的二进制在线升级不会替换容器内的 ffmpeg/ffprobe。修复工具镜像后，还需等待 Songloft 构建同步基础镜像，再拉取并重建容器；仅升级 Songloft 可执行文件不能补齐旧工具的能力。

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。
