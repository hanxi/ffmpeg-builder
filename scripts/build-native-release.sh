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
cd "$source"

common=(
  --prefix="$destination/prefix" --disable-everything --enable-ffmpeg
  --enable-ffprobe --disable-ffplay --enable-static --disable-shared
  --disable-debug --disable-doc --enable-small
  --enable-protocol=file,pipe,http,https,tcp,udp,tls,crypto --enable-openssl
  --enable-demuxer=mp3,aac,flac,ogg,wav,matroska,mov,ape,wv,asf,image2,mpegps,mpegts,avi,flv,rm,mpegvideo,h264,hevc,m4v,ac3,hls
  --enable-muxer=mp3,flac,ogg,wav,matroska,adts,ipod,hls,mpegts
  --enable-decoder=mp3,mp3float,aac,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_s32le,alac,ape,wavpack,wmav1,wmav2,mjpeg,png,mp2,mp2float,ac3,eac3,dca,cook
  --enable-decoder=h264,hevc,vp8,vp9,mpeg1video,mpeg2video,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,vc1,flv,h263,rv10,rv20,rv30,rv40,theora
  --enable-encoder=flac,pcm_s16le,pcm_s24le,pcm_s32le,aac,mjpeg,png
  --enable-parser=mpegaudio,aac,flac,opus,h264,hevc,mpegvideo,mpeg4video,vp8,vp9,vc1,ac3,dca
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,extract_extradata
  --enable-filter=aresample,anull,loudnorm,scale,format,null,atempo
  --enable-version3
  --enable-zlib --pkg-config-flags=--static
)

case "$target" in
  linux-x86_64) host=x86_64-linux-gnu ;;
  linux-arm64) host=aarch64-linux-gnu; common+=(--target-os=linux --arch=aarch64 --enable-cross-compile) ;;
  linux-armv7) host=arm-linux-gnueabihf; common+=(--target-os=linux --arch=arm --enable-cross-compile) ;;
  windows-x86_64) host=x86_64-w64-mingw32; common+=(--target-os=mingw32 --arch=x86_64) ;;
  macos-arm64) host=arm64-apple-darwin; common+=(--target-os=darwin --arch=aarch64) ;;
  macos-x86_64) host=x86_64-apple-darwin; common+=(--target-os=darwin --arch=x86_64) ;;
  android-arm64-v8a) host=aarch64-linux-android; common+=(--target-os=android --arch=aarch64 --enable-cross-compile) ;;
  android-armeabi-v7a) host=armv7a-linux-androideabi; common+=(--target-os=android --arch=armv7-a --enable-cross-compile) ;;
  android-x86_64) host=x86_64-linux-android; common+=(--target-os=android --arch=x86_64 --enable-cross-compile) ;;
  ios-arm64) host=arm64-apple-darwin; common+=(--target-os=darwin --arch=aarch64 --enable-cross-compile --disable-programs --disable-doc) ;;
  *) echo "unsupported FFmpeg release target: $target" >&2; exit 2 ;;
esac

if [[ "$target" == linux-x86_64 ]]; then
  common+=(--enable-gpl --enable-muxer=chromaprint --enable-chromaprint --enable-libmp3lame --enable-libvorbis --enable-libopus --enable-libx264 --enable-encoder=libmp3lame,libvorbis,libopus,libx264)
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
  common+=(--sysroot="${ANDROID_NDK_SYSROOT:?ANDROID_NDK_SYSROOT is required}" --extra-cflags="-fPIC" --extra-ldflags="-fuse-ld=lld")
fi
if [[ "$target" == ios-arm64 ]]; then
  common+=(--extra-cflags="-miphoneos-version-min=15.0" --extra-ldflags="-miphoneos-version-min=15.0")
fi

./configure "${common[@]}" ${FFMPEG_EXTRA_CONFIGURE_ARGS:-}
make -j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
make install

if [[ "$target" == ios-arm64 ]]; then
  mkdir -p "$destination/framework"
  find "$destination/prefix" -name '*.a' -exec cp {} "$destination/framework/" \;
  test -n "$(find "$destination/framework" -type f -name '*.a' -print -quit)"
else
  mkdir -p "$destination/bin"
  extension=
  [[ "$target" == windows-x86_64 ]] && extension=.exe
  cp "$destination/prefix/bin/ffmpeg" "$destination/bin/ffmpeg$extension"
  cp "$destination/prefix/bin/ffprobe" "$destination/bin/ffprobe$extension"
fi
