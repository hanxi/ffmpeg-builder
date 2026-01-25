FROM alpine:3.20 AS builder
LABEL stage=ffprobe-builder

RUN apk add --no-cache \
    build-base \
    yasm \
    nasm \
    pkgconfig \
    zlib-dev \
    curl

ENV FFMPEG_VERSION=8.0.1
ENV FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2

WORKDIR /build

RUN curl -fL "$FFMPEG_URL" -o ffmpeg.tar.bz2 \
    && tar -xjf ffmpeg.tar.bz2

WORKDIR /build/ffmpeg-${FFMPEG_VERSION}

RUN ./configure \
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
    --extra-ldflags="-static" \
    && make -j$(nproc) && make install

FROM scratch AS runtime

COPY --from=builder /opt/ffprobe/bin/ffprobe /ffprobe

ENTRYPOINT ["/ffprobe"]
CMD ["-h"]
