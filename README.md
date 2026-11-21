# FFmpeg Builder

一个轻量级的 Docker 镜像构建器，用于创建包含静态编译的 ffmpeg 和 ffprobe 可执行文件的最小镜像。保留音频能力 + 视频解码转 HLS（H.264/AAC）能力，内置 chromaprint 音频指纹支持。

[English](README.en.md)

## 特性

- 基于 Alpine Linux 3.20 构建
- 静态编译的 ffmpeg + ffprobe 可执行文件
- 源码下载最多重试 5 次，包括 TLS/连接重置，并设置连接、单次下载及重试时间上限
- 最小化运行时镜像（基于 scratch）
- 音频编解码 + 常见视频容器解码、libx264 编码输出 HLS
- 普通 HLS 输入与 AES-128 加密分片读取（`hls` demuxer + `crypto` 协议）
- 音频滤镜：aresample（重采样）、loudnorm（EBU R128 音量均衡）、atempo（变速不变调，0.5–2.0 倍速播放）
- 内置 chromaprint muxer，支持 AcoustID 音频指纹识别（无需独立 fpcalc）
- 发布 Linux、Windows、macOS、Android 和 iOS 资产，并为每个 ABI 生成固定名称与 SHA-256

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

## 多平台 Release 资产

`release-assets.yml` 构建十个目标的压缩资产。修改 `Dockerfile`、`scripts/**`、`tests/**` 或该 workflow 后推送到 `main`，会更新 `dev`。推送 `vX.Y.Z` tag 发布对应的稳定资产。手动运行 **Actions → Release FFmpeg assets** 时，开发通道选择 `channel=dev`、`release_tag=dev`，稳定通道选择 `channel=stable` 和具体版本 tag。发布包含 `manifest.json`、`checksums.txt` 和各平台归档。归档内的 `asset.json` 记录目标、源码提交和 GPL 许可证。

Docker 镜像由独立的 `build-ffprobe.yml` 构建。它监听针对 `main` 且涉及 `Dockerfile`、`tests/**` 或该 workflow 的 push 和 pull request。纯文档更新不启动这两个 workflow。已有 Release 使用同名资产覆盖上传，核对构建时应查看附件摘要和 manifest。

[最新正式版](https://github.com/hanxi/ffmpeg-builder/releases/latest) · [dev](https://github.com/hanxi/ffmpeg-builder/releases/tag/dev) · [完整包名](https://songloft.hanxi.cc/release-packages)

本地可用平台工具链生成单项资产：

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

Bundle 构建先解析 `dev` 或稳定 Release，再按 manifest 校验 tag、平台、ABI、大小和 SHA-256。解析结果会保存具体 Release tag、FFmpeg 源码提交和资产摘要。构建矩阵始终复用这份结果，不直接下载没有版本约束的 `latest` 文件。

iOS 的 arm64 资产包含 `framework/libsongloft_ffmpeg.a`、公开头文件和 `link-flags.txt`，供 gomobile 静态链接。Android 资产提供可放入 APK `lib/<ABI>/` 的位置无关可执行文件，构建校验 ELF 解释器、系统依赖和 16 KiB 对齐。各 Bundle 目标包含 MP3、Vorbis、H.264 和 Chromaprint 支持。

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。
