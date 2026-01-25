# FFprobe Builder

一个轻量级的 Docker 镜像构建器，用于创建包含静态编译的 ffprobe 可执行文件的最小镜像。

## 📦 特性

- 基于 Alpine Linux 3.20 构建
- 静态编译的 ffprobe 可执行文件
- 最小化运行时镜像（基于 scratch）
- 支持多种音视频格式解析
- 超小镜像体积（约 10MB）

## 🚀 快速开始

### 构建镜像

```bash
docker build -t ffprobe .
```

### 运行容器

```bash
# 显示帮助信息
docker run --rm ffprobe

# 分析媒体文件
docker run --rm -v /path/to/media:/media ffprobe /media/video.mp4

# 获取详细的 JSON 格式输出
docker run --rm -v /path/to/media:/media ffprobe -v quiet -print_format json -show_format -show_streams /media/video.mp4
```

## 🛠️ 技术细节

### 编译配置

该镜像使用以下配置编译 ffprobe：

```bash
./configure \
    --prefix=/opt/ffprobe \
    --disable-everything \
    --disable-ffmpeg \
    --disable-ffplay \
    --enable-ffprobe \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-doc \
    --disable-network \
    --enable-protocol=file \
    --enable-demuxer=mov,matroska,mp3,ogg,wav,flac,aac \
    --enable-parser=aac,mpeg4video \
    --enable-decoder=aac,mp3,flac,pcm_s16le,vorbis \
    --enable-zlib \
    --extra-cflags="-static" \
    --extra-ldflags="-static"
```

### 支持的格式

**Demuxers:**
- mov (MP4/MOV)
- matroska (MKV)
- mp3
- ogg
- wav
- flac
- aac

**Decoders:**
- aac
- mp3
- flac
- pcm_s16le
- vorbis

**Parsers:**
- aac
- mpeg4video

## 📊 镜像大小

```
REPOSITORY   TAG       IMAGE ID       CREATED          SIZE
ffprobe      latest    xxxxxxxxxx     xx minutes ago   10.2MB
```

## 📝 使用示例

### 基本用法

```bash
# 查看文件基本信息
docker run --rm -v $(pwd):/data ffprobe /data/sample.mp4

# 显示详细流信息
docker run --rm -v $(pwd):/data ffprobe -show_streams /data/sample.mp4

# 以 JSON 格式输出
docker run --rm -v $(pwd):/data ffprobe -v quiet -print_format json -show_format /data/sample.mp4
```

### 在脚本中使用

```bash
#!/bin/bash
VIDEO_FILE="/path/to/video.mp4"

# 获取视频时长
duration=$(docker run --rm -v "$(dirname $VIDEO_FILE)":/data ffprobe -v quiet -show_entries format=duration -of csv=p=0 /data/$(basename $VIDEO_FILE))

echo "视频时长: ${duration} 秒"
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。