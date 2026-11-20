#!/usr/bin/env bash
set -euo pipefail

target=${1:?target is required}
root=${2:?destination is required}
prefix="$root/deps"
mkdir -p "$prefix"
cd "$root"

fetch() {
  local name=$1 url=$2
  curl -fL --retry 5 --retry-all-errors --connect-timeout 30 --max-time 600 "$url" -o "$name.tar"
  mkdir -p "$name"
  tar -xf "$name.tar" --strip-components=1 -C "$name"
}

case "$target" in
  linux-arm64) host=aarch64-linux-gnu; system=Linux ;;
  linux-armv7) host=arm-linux-gnueabihf; system=Linux ;;
  windows-x86_64) host=x86_64-w64-mingw32; system=Windows ;;
  macos-arm64|macos-x86_64) system=Darwin ;;
  ios-arm64) host=aarch64-apple-darwin; system=iOS ;;
  android-arm64-v8a) host=aarch64-linux-android; system=Android; openssl=android-arm64 ;;
  android-armeabi-v7a) host=arm-linux-androideabi; system=Android; openssl=android-arm ;;
  android-x86_64) host=x86_64-linux-android; system=Android; openssl=android-x86_64 ;;
  *) echo "unsupported dependency target: $target" >&2; exit 2 ;;
esac

autotools=(--prefix="$prefix" --disable-shared --enable-static)
x264=(--prefix="$prefix" --enable-static --disable-cli --disable-opencl --disable-asm --enable-pic)
cmake_args=()
if [[ -n "${host:-}" ]]; then
  autotools+=(--host="$host")
  x264+=(--host="$host")
  cmake_args+=(-DCMAKE_SYSTEM_NAME="$system" -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY)
fi
if [[ -n "${CROSS_PREFIX:-}" ]]; then
  x264+=(--cross-prefix="$CROSS_PREFIX")
fi
case "$system" in
  Android)
    export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
    export CXX="${CC%clang}clang++"
    export STRINGS=llvm-strings STRIP=llvm-strip
    export PKGCONFIG=pkg-config
    cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI="${target#android-}" -DANDROID_PLATFORM="android-$ANDROID_API" -DANDROID_STL=c++_static)
    ;;
  iOS)
    export CC="$(xcrun --sdk iphoneos -f clang)"
    export CXX="$(xcrun --sdk iphoneos -f clang++)"
    export CFLAGS="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=15.0"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="$CFLAGS"
    cmake_args+=(-DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0)
    ;;
  Darwin)
    export CC=clang CXX=clang++
    cmake_args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
    ;;
  *)
    export CC="${CROSS_PREFIX}gcc" CXX="${CROSS_PREFIX}g++"
    cmake_args+=(-DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX")
    ;;
esac

export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
build_autotools() (
  cd "$1"
  shift
  ./configure "${autotools[@]}" "$@"
  make -j"$jobs"
  make install
)

fetch lame https://deb.debian.org/debian/pool/main/l/lame/lame_3.100.orig.tar.gz
# LAME still compiles mpglib with the decoder disabled. Its generated
# configure cannot run the standard C headers probe for an iOS cross build.
lame_options=(--disable-frontend --disable-decoder)
if [[ "$system" == iOS ]]; then
  lame_options+=(ac_cv_header_stdc=yes)
fi
build_autotools lame "${lame_options[@]}"
fetch ogg https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz
build_autotools ogg
fetch vorbis https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz
if [[ "$system" == Darwin || "$system" == iOS ]]; then
  # Recent Apple linkers reject this legacy Vorbis configure flag.
  sed -i.bak 's/ -force_cpusubtype_ALL//g' vorbis/configure
fi
build_autotools vorbis --with-ogg="$prefix" --disable-docs --disable-examples
fetch opus https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
build_autotools opus --disable-doc --disable-extra-programs

x264_commit=31e19f92f00c7003fa115047ce50978bc98c3a0d
fetch x264 "https://github.com/mirror/x264/archive/$x264_commit.tar.gz"
(
  cd x264
  ./configure "${x264[@]}"
  make -j"$jobs"
  make install
)

fetch chromaprint https://github.com/acoustid/chromaprint/releases/download/v1.6.0/chromaprint-1.6.0.tar.gz
cmake -S chromaprint -B chromaprint/build "${cmake_args[@]}" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DKISSFFT_SOURCE_DIR="$root/chromaprint/src/3rdparty/kissfft" \
  -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DFFT_LIB=kissfft
cmake --build chromaprint/build --parallel "$jobs"
cmake --install chromaprint/build
case "$system" in
  Android) cxx_libs="-lc++_static -lc++abi" ;;
  Darwin|iOS) cxx_libs="-lc++" ;;
  Windows) cxx_libs="-l:libstdc++.a -l:libwinpthread.a" ;;
  *) cxx_libs="-l:libstdc++.a" ;;
esac
if [[ "$system" == Windows ]]; then
  sed -i.bak '/^Cflags:/s/$/ -DCHROMAPRINT_NODLL/' "$prefix/lib/pkgconfig/libchromaprint.pc"
fi
printf '\nLibs.private: %s -lm\n' "$cxx_libs" >> "$prefix/lib/pkgconfig/libchromaprint.pc"

# Windows/macOS/iOS use the system TLS implementation. Android needs a TLS
# library that can be linked for every target ABI.
if [[ "$system" == Android ]]; then
  fetch openssl https://github.com/openssl/openssl/releases/download/openssl-3.5.5/openssl-3.5.5.tar.gz
  (
    cd openssl
    # OpenSSL selects the NDK compiler itself using ANDROID_NDK_ROOT and PATH.
    unset CC CXX CROSS_PREFIX
    ./Configure "$openssl" "-D__ANDROID_API__=$ANDROID_API" --prefix="$prefix" --libdir=lib no-shared no-tests no-apps
    make -j"$jobs"
    make install_sw
  )
fi
