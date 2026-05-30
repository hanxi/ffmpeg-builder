FROM alpine:3.20 AS builder
LABEL stage=ffmpeg-builder

RUN apk add --no-cache \
    build-base \
    yasm \
    nasm \
    pkgconfig \
    zlib-dev \
    zlib-static \
    lame-dev \
    libogg-dev \
    libogg-static \
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

# 构建 ffmpeg + ffprobe（仅音频，完全静态链接）
ENV FFMPEG_VERSION=8.0.1
ENV FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2

WORKDIR /build

RUN curl -fL "$FFMPEG_URL" -o ffmpeg.tar.bz2 \
    && tar -xjf ffmpeg.tar.bz2

WORKDIR /build/ffmpeg-${FFMPEG_VERSION}

# 分开 configure 和 make 以便定位错误
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
    --disable-network \
    --enable-small \
    \
    --enable-protocol=file \
    --enable-protocol=pipe \
    \
    --enable-demuxer=mp3,aac,flac,ogg,wav,matroska,mov,ape,wv \
    --enable-muxer=mp3,flac,ogg,wav,matroska,adts,ipod \
    \
    --enable-decoder=mp3,mp3float,aac,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_s32le,alac,ape,wavpack \
    --enable-encoder=libmp3lame,flac,libvorbis,libopus,pcm_s16le,pcm_s24le,aac \
    \
    --enable-parser=mpegaudio,aac,flac,opus \
    \
    --enable-filter=aresample,anull \
    \
    --enable-libmp3lame \
    --enable-libvorbis \
    --enable-libopus \
    --enable-zlib \
    --extra-cflags="-static" \
    --extra-ldflags="-static"

RUN make -j$(nproc) && make install

FROM scratch AS runtime

COPY --from=builder /opt/ffmpeg/bin/ffmpeg /ffmpeg
COPY --from=builder /opt/ffmpeg/bin/ffprobe /ffprobe

ENTRYPOINT ["/ffmpeg"]
CMD ["-h"]
