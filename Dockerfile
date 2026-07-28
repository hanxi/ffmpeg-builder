FROM alpine:3.20 AS builder
LABEL stage=ffmpeg-builder

RUN apk add --no-cache \
    build-base \
    bash \
    cmake \
    yasm \
    nasm \
    pkgconfig \
    zlib-dev \
    zlib-static \
    lame-dev \
    libogg-dev \
    libogg-static \
    openssl-dev \
    openssl-libs-static \
    curl

WORKDIR /src

# 构建 libvorbis 静态库（Alpine 无 vorbis-static 包）
ENV VORBIS_VERSION=1.3.7
RUN curl -fL "https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.xz" -o libvorbis.tar.xz \
    && tar -xJf libvorbis.tar.xz \
    && cd libvorbis-${VORBIS_VERSION} \
    && ./configure --prefix=/usr --enable-static --disable-shared --disable-docs --disable-examples \
    && make -j$(nproc) && make install

# 构建 libopus 静态库（Alpine 无 opus-static 包）
ENV OPUS_VERSION=1.5.2
RUN curl -fL "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" -o opus.tar.gz \
    && tar -xzf opus.tar.gz \
    && cd opus-${OPUS_VERSION} \
    && ./configure --prefix=/usr --enable-static --disable-shared --disable-doc --disable-extra-programs \
    && make -j$(nproc) && make install

# 构建 libchromaprint 静态库（使用内置 kissfft，不依赖 ffmpeg）
ENV CHROMAPRINT_VERSION=1.6.0
RUN curl -fL "https://github.com/acoustid/chromaprint/releases/download/v${CHROMAPRINT_VERSION}/chromaprint-${CHROMAPRINT_VERSION}.tar.gz" -o chromaprint.tar.gz \
    && tar -xzf chromaprint.tar.gz \
    && cd chromaprint-${CHROMAPRINT_VERSION} \
    && cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_TOOLS=OFF \
        -DBUILD_TESTS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DFFT_LIB=kissfft \
    && cmake --build build -j$(nproc) \
    && cmake --install build \
    && echo 'Libs.private: -lstdc++ -lm' >> /usr/lib/pkgconfig/libchromaprint.pc

# 构建 libx264 静态库（Web 视频 HLS 转码用；Alpine 的 x264-dev 无静态库）
RUN curl -fL "https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.bz2" -o x264.tar.bz2 \
    && tar -xjf x264.tar.bz2 \
    && cd x264-stable \
    && ./configure --prefix=/usr --enable-static --enable-pic --disable-cli --disable-opencl \
    && make -j$(nproc) && make install

# 构建 ffmpeg + ffprobe（音频 + 视频转 HLS，完全静态链接，内置 chromaprint muxer）
ENV FFMPEG_VERSION=8.0.1
ENV FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2

WORKDIR /build

RUN curl -fL "$FFMPEG_URL" -o ffmpeg.tar.bz2 \
    && tar -xjf ffmpeg.tar.bz2

WORKDIR /build/ffmpeg-${FFMPEG_VERSION}

RUN ./configure \
    --prefix=/opt/ffmpeg \
    --disable-everything \
    --enable-ffmpeg \
    --enable-ffprobe \
    --disable-ffplay \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-doc \
    --enable-small \
    \
    --enable-protocol=file \
    --enable-protocol=pipe \
    --enable-protocol=http \
    --enable-protocol=https \
    --enable-protocol=tcp \
    --enable-protocol=udp \
    --enable-protocol=tls \
    --enable-openssl \
    \
    --enable-demuxer=mp3,aac,flac,ogg,wav,matroska,mov,ape,wv,asf,image2,mpegps,mpegts,avi,flv,rm,mpegvideo,h264,hevc,m4v,ac3 \
    --enable-muxer=mp3,flac,ogg,wav,matroska,adts,ipod,chromaprint,hls,mpegts \
    \
    --enable-decoder=mp3,mp3float,aac,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_s32le,alac,ape,wavpack,wmav1,wmav2,mjpeg,png,mp2,mp2float,ac3,eac3,dca,cook \
    --enable-decoder=h264,hevc,vp8,vp9,mpeg1video,mpeg2video,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,vc1,flv,h263,rv10,rv20,rv30,rv40,theora \
    --enable-encoder=libmp3lame,flac,libvorbis,libopus,pcm_s16le,pcm_s24le,aac,mjpeg,png,libx264 \
    \
    --enable-parser=mpegaudio,aac,flac,opus,h264,hevc,mpegvideo,mpeg4video,vp8,vp9,vc1,ac3,dca \
    \
    --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,extract_extradata \
    \
    --enable-filter=aresample,anull,loudnorm,scale,format,null \
    \
    --enable-gpl \
    --enable-version3 \
    --enable-chromaprint \
    --enable-libmp3lame \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libx264 \
    --enable-zlib \
    --pkg-config-flags="--static" \
    --extra-cflags="-static" \
    --extra-ldflags="-static"

RUN make -j$(nproc) && make install

FROM scratch AS runtime

COPY --from=builder /opt/ffmpeg/bin/ffmpeg /ffmpeg
COPY --from=builder /opt/ffmpeg/bin/ffprobe /ffprobe

ENTRYPOINT ["/ffmpeg"]
CMD ["-h"]
