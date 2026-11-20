#!/usr/bin/env bash
set -euo pipefail

# Build one release target from a checked-out FFmpeg source tree. The feature
# list intentionally mirrors Dockerfile. Platform runners provide the native
# compiler and static dependency prefixes.
target=${1:?target is required}
destination=${2:?destination is required}
source=${FFMPEG_SOURCE_DIR:?FFMPEG_SOURCE_DIR must point to the extracted FFmpeg source}
version=${FFMPEG_VERSION:-8.0.1}
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
if [[ "$target" == macos-* ]]; then
  export MACOSX_DEPLOYMENT_TARGET=13.0
fi
if [[ "$target" != linux-x86_64 ]]; then
  "$(dirname "$0")/build-release-dependencies.sh" "$target" "$destination"
  export PKG_CONFIG_LIBDIR="$destination/deps/lib/pkgconfig"
  export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
fi
cd "$source"

common=(
  --prefix="$destination/prefix" --disable-everything --enable-ffmpeg
  --enable-ffprobe --disable-ffplay --enable-static --disable-shared
  --disable-debug --disable-doc --enable-small
  --enable-protocol=file,pipe,http,https,tcp,udp,tls,crypto
  --enable-demuxer=mp3,aac,flac,ogg,wav,matroska,mov,ape,wv,asf,image2,mpegps,mpegts,avi,flv,rm,mpegvideo,h264,hevc,m4v,ac3,hls
  --enable-muxer=mp3,flac,ogg,wav,matroska,adts,ipod,hls,mpegts,image2pipe,chromaprint
  --enable-decoder=mp3,mp3float,aac,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_s32le,alac,ape,wavpack,wmav1,wmav2,mjpeg,png,mp2,mp2float,ac3,eac3,dca,cook
  --enable-decoder=h264,hevc,vp8,vp9,mpeg1video,mpeg2video,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,vc1,flv,h263,rv10,rv20,rv30,rv40,theora
  --enable-encoder=flac,pcm_s16le,pcm_s24le,pcm_s32le,aac,mjpeg,png,libmp3lame,libvorbis,libopus,libx264
  --enable-parser=mpegaudio,aac,flac,opus,h264,hevc,mpegvideo,mpeg4video,vp8,vp9,vc1,ac3,dca
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,extract_extradata
  --enable-filter=aresample,anull,loudnorm,scale,format,aformat,null,atempo
  --enable-gpl --enable-version3
  --enable-libmp3lame --enable-libvorbis --enable-libopus --enable-libx264 --enable-chromaprint
  --pkg-config=pkg-config --pkg-config-flags=--static
)

case "$target" in
  linux-x86_64) host=x86_64-linux-gnu ;;
  linux-arm64) host=aarch64-linux-gnu; common+=(--target-os=linux --arch=aarch64 --enable-cross-compile) ;;
  linux-armv7) host=arm-linux-gnueabihf; common+=(--target-os=linux --arch=arm --enable-cross-compile) ;;
  windows-x86_64) host=x86_64-w64-mingw32; common+=(--target-os=mingw32 --arch=x86_64 --enable-cross-compile) ;;
  macos-arm64) host=arm64-apple-darwin; common+=(--target-os=darwin --arch=aarch64) ;;
  macos-x86_64) host=x86_64-apple-darwin; common+=(--target-os=darwin --arch=x86_64) ;;
  android-arm64-v8a) host=aarch64-linux-android; common+=(--target-os=android --arch=aarch64 --enable-cross-compile) ;;
  android-armeabi-v7a) host=armv7a-linux-androideabi; common+=(--target-os=android --arch=armv7-a --enable-cross-compile) ;;
  android-x86_64) host=x86_64-linux-android; common+=(--target-os=android --arch=x86_64 --enable-cross-compile) ;;
  ios-arm64) host=arm64-apple-darwin; common+=(--target-os=darwin --arch=aarch64 --enable-cross-compile --disable-programs --disable-doc) ;;
  *) echo "unsupported FFmpeg release target: $target" >&2; exit 2 ;;
esac

if [[ "$target" == linux-x86_64 ]]; then
  common+=(--enable-zlib --enable-openssl)
else
  common+=(--extra-cflags="-I$destination/deps/include" --extra-ldflags="-L$destination/deps/lib")
fi
if [[ "$target" != linux-x86_64 && -n "${CROSS_PREFIX:-}" ]]; then
  common+=(--cross-prefix="$CROSS_PREFIX")
fi
if [[ "$target" != linux-x86_64 && -n "${CC:-}" ]]; then
  common+=(--cc="$CC")
fi
if [[ -n "${NM:-}" ]]; then
  common+=(--nm="$NM")
fi
if [[ -n "${AR:-}" ]]; then
  common+=(--ar="$AR")
fi
if [[ -n "${RANLIB:-}" ]]; then
  common+=(--ranlib="$RANLIB")
fi
if [[ "$target" == windows-x86_64 || "$target" == android-x86_64 ]]; then
  common+=(--disable-x86asm)
fi
if [[ "$target" == android-* && -n "${ANDROID_API:-}" ]]; then
  common+=(--strip="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip")
  common+=(--enable-openssl --enable-pic --sysroot="${ANDROID_NDK_SYSROOT:?ANDROID_NDK_SYSROOT is required}" --extra-cflags="-fPIC" --extra-ldflags="-fuse-ld=lld -pie -Wl,-z,max-page-size=16384")
fi
if [[ "$target" == ios-arm64 ]]; then
  sdk=$(xcrun --sdk iphoneos --show-sdk-path)
  common+=(--cc="$(xcrun --sdk iphoneos -f clang)" --sysroot="$sdk"
    --disable-autodetect --enable-securetransport --enable-swscale --enable-swresample
    --extra-cflags="-arch arm64 -miphoneos-version-min=15.0"
    --extra-ldflags="-arch arm64 -miphoneos-version-min=15.0")
elif [[ "$target" == macos-* ]]; then
  # Homebrew on the Intel runner can otherwise add undeclared X11 libraries.
  common+=(--disable-autodetect --enable-securetransport --enable-zlib)
elif [[ "$target" == windows-* ]]; then
  common+=(--enable-schannel --extra-ldflags="-static-libgcc")
fi

if ! ./configure "${common[@]}" ${FFMPEG_EXTRA_CONFIGURE_ARGS:-}; then
  if [[ -f ffbuild/config.log ]]; then
    tail -n 140 ffbuild/config.log >&2
  fi
  exit 1
fi
if [[ "$target" == windows-x86_64 ]]; then
  make -j2
else
  make -j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
fi
make install

if [[ "$target" == ios-arm64 ]]; then
  mkdir -p "$destination/framework"
  cp -R "$destination/prefix/include" "$destination/framework/"
  xcrun --sdk iphoneos libtool -static -o "$destination/framework/libsongloft_ffmpeg.a" \
    "$destination"/prefix/lib/libav*.a "$destination"/prefix/lib/libsw*.a "$destination"/deps/lib/*.a
  printf '%s\n' '-lc++ -framework Security -framework CoreFoundation' > "$destination/framework/link-flags.txt"
else
  mkdir -p "$destination/bin"
  extension=
  source_extension=
  if [[ "$target" == windows-x86_64 ]]; then
    extension=.exe
    source_extension=.exe
  fi
  cp "$destination/prefix/bin/ffmpeg$source_extension" "$destination/bin/ffmpeg$extension"
  cp "$destination/prefix/bin/ffprobe$source_extension" "$destination/bin/ffprobe$extension"
  if [[ "$target" == macos-* ]]; then
    for program in "$destination/bin/"*; do
      otool -L "$program" > "$destination/macos-dependencies.txt"
      awk 'NR > 1 && $1 !~ /^\/(usr\/lib|System\/Library)\// { print; invalid = 1 }
           END { exit invalid }' "$destination/macos-dependencies.txt"
    done
  elif [[ "$target" == android-* ]]; then
    readelf="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
    for program in "$destination/bin/"*; do
      "$readelf" -h "$program" > "$destination/elf-header.txt"
      "$readelf" -lW "$program" > "$destination/elf-segments.txt"
      "$readelf" -d "$program" > "$destination/elf-dynamic.txt"
      grep -E 'Type:.*DYN' "$destination/elf-header.txt"
      grep -F 'Requesting program interpreter: /system/bin/linker' "$destination/elf-segments.txt"
      # libz is part of the public NDK alongside the Bionic runtime.
      if grep -E 'Shared library:' "$destination/elf-dynamic.txt" | grep -Ev '\[(libc|libm|libdl|liblog|libz)\.so\]'; then
        echo "Unexpected Android runtime dependency in $program" >&2
        exit 1
      fi
      python3 - "$destination/elf-segments.txt" <<'PYELF'
import pathlib
import sys

segments = [line.split() for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
alignments = [int(line[-1], 16) for line in segments if line and line[0] == "LOAD"]
if not alignments or min(alignments) < 16384:
    raise SystemExit("Android ELF LOAD segments require 16 KiB alignment")
PYELF
    done
  fi
fi
