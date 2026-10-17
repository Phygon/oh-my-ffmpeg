# syntax=docker/dockerfile:1
ARG DEBIAN_VERSION=bookworm

# ---------- Build stage: compile libsrt (static) and FFmpeg ----------
FROM debian:${DEBIAN_VERSION}-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget xz-utils build-essential cmake pkg-config nasm yasm \
        autoconf automake libtool meson ninja-build \
        tclsh zlib1g-dev libssl-dev libfreetype6-dev libfontconfig-dev libharfbuzz-dev \
        libnuma-dev \
        libasound2-dev libpulse-dev libjack-jackd2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# ---- x264: static library (H.264 encoder) ----
ARG X264_REF=27d83708
RUN wget -q https://code.videolan.org/videolan/x264/-/archive/${X264_REF}/x264-${X264_REF}.tar.bz2 -O x264.tar.bz2 \
    && tar -xjf x264.tar.bz2 \
    && mv x264-${X264_REF} /src/x264 \
    && rm x264.tar.bz2 \
    && cd /src/x264 \
    && ./configure --prefix=/usr/local --enable-static --disable-shared --disable-cli \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/x264

# ---- x265: static library (HEVC encoder) ----
ARG X265_VERSION=4.2
RUN wget -q https://get.videolan.org/x265/x265_${X265_VERSION}.tar.gz -O x265.tar.gz \
    && tar -xzf x265.tar.gz \
    && mv x265_${X265_VERSION} /src/x265 \
    && rm x265.tar.gz \
    && cmake -S /src/x265/source -B /src/x265-build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
    && cmake --build /src/x265-build -j"$(nproc)" \
    && cmake --install /src/x265-build \
    && rm -rf /src/x265-build /src/x265

# ---- SVT-AV1: static library (AV1 encoder) ----
ARG SVTAV1_VERSION=4.2.0
RUN wget -q https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v${SVTAV1_VERSION}/SVT-AV1-v${SVTAV1_VERSION}.tar.gz -O svtav1.tar.gz \
    && tar -xzf svtav1.tar.gz \
    && mv SVT-AV1-v${SVTAV1_VERSION} /src/svt-av1 \
    && rm svtav1.tar.gz \
    && cmake -S /src/svt-av1 -B /src/svt-av1-build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_APPS=OFF \
        -DBUILD_TESTING=OFF \
    && cmake --build /src/svt-av1-build -j"$(nproc)" \
    && cmake --install /src/svt-av1-build \
    && rm -rf /src/svt-av1-build /src/svt-av1

# ---- libaom: static library (AV1 reference codec) ----
ARG LIBAOM_VERSION=3.15.1
RUN wget -q https://storage.googleapis.com/aom-releases/libaom-${LIBAOM_VERSION}.tar.gz -O libaom.tar.gz \
    && tar -xzf libaom.tar.gz \
    && mv libaom-${LIBAOM_VERSION} /src/libaom \
    && rm libaom.tar.gz \
    && cmake -S /src/libaom -B /src/libaom-build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=0 \
        -DENABLE_TESTS=0 \
        -DENABLE_EXAMPLES=0 \
        -DENABLE_TOOLS=0 \
        -DENABLE_DOCS=0 \
    && cmake --build /src/libaom-build -j"$(nproc)" \
    && cmake --install /src/libaom-build \
    && rm -rf /src/libaom-build /src/libaom

# ---- libvpx: static library (VP8/VP9) ----
ARG LIBVPX_VERSION=1.17.0
RUN wget -q https://github.com/webmproject/libvpx/archive/refs/tags/v${LIBVPX_VERSION}.tar.gz -O libvpx.tar.gz \
    && tar -xzf libvpx.tar.gz \
    && mv libvpx-${LIBVPX_VERSION} /src/libvpx \
    && rm libvpx.tar.gz \
    && cd /src/libvpx \
    && ./configure --prefix=/usr/local --enable-vp8 --enable-vp9 --disable-examples --disable-tools --disable-docs --disable-unit-tests \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/libvpx

# ---- fdk-AAC: static library (AAC encoder, non-redistributable) ----
ARG FDKAAC_VERSION=2.0.3
RUN wget -q https://github.com/mstorsjo/fdk-aac/archive/refs/tags/v${FDKAAC_VERSION}.tar.gz -O fdk-aac.tar.gz \
    && tar -xzf fdk-aac.tar.gz \
    && mv fdk-aac-${FDKAAC_VERSION} /src/fdk-aac \
    && rm fdk-aac.tar.gz \
    && cd /src/fdk-aac \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local --disable-shared --enable-static \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/fdk-aac

# ---- Opus: static library (audio codec) ----
ARG OPUS_VERSION=1.6.1
RUN wget -q https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz -O opus.tar.gz \
    && tar -xzf opus.tar.gz \
    && mv opus-${OPUS_VERSION} /src/opus \
    && rm opus.tar.gz \
    && cd /src/opus \
    && ./configure --prefix=/usr/local --disable-shared --enable-static --disable-doc --disable-extra-programs \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/opus

# ---- librist: static library (RIST protocol) ----
ARG LIBRIST_VERSION=0.2.20
RUN wget -q https://code.videolan.org/rist/librist/-/archive/v${LIBRIST_VERSION}/librist-v${LIBRIST_VERSION}.tar.gz -O librist.tar.gz \
    && tar -xzf librist.tar.gz \
    && mv librist-v${LIBRIST_VERSION} /src/librist \
    && rm librist.tar.gz \
    && meson setup /src/librist-build /src/librist --prefix=/usr/local --libdir=lib --default-library=static \
    && meson compile -C /src/librist-build -j"$(nproc)" \
    && meson install -C /src/librist-build \
    && rm -rf /src/librist-build

# ---- libsrt: static library (SRT protocol) ----
ARG SRT_VERSION=1.5.7
RUN wget -q https://github.com/Haivision/srt/archive/refs/tags/v${SRT_VERSION}.tar.gz -O srt.tar.gz \
    && tar -xzf srt.tar.gz \
    && mv srt-${SRT_VERSION} /src/srt \
    && rm srt.tar.gz \
    && cmake -S /src/srt -B /src/srt-build \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON \
        -DENABLE_APPS=OFF \
    && cmake --build /src/srt-build -j"$(nproc)" \
    && cmake --install /src/srt-build \
    && rm -rf /src/srt-build /src/srt

# ---- zimg: static library for high-quality scaling and colour conversion (zscale filter) ----
ARG ZIMG_VERSION=3.0.6
RUN wget -q https://github.com/sekrit-twc/zimg/archive/refs/tags/release-${ZIMG_VERSION}.tar.gz -O zimg.tar.gz \
    && tar -xzf zimg.tar.gz \
    && mv zimg-release-${ZIMG_VERSION} /src/zimg \
    && rm zimg.tar.gz \
    && cd /src/zimg \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local --enable-static --disable-shared --disable-testapp \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/zimg

# ---- Blackmagic DeckLink SDK headers (build time only; not part of dist/ or the runtime image) ----
# Empty DECKLINK_SDK_VERSION copies only the placeholder folder, which adds no headers.
ARG DECKLINK_SDK_VERSION=
COPY blackmagic_${DECKLINK_SDK_VERSION:-none}/include/ /usr/local/include/

# ---- FFmpeg ----
ARG FFMPEG_VERSION=9.0.2 FFMPEG_EXTRA_VERSION=1~custom
RUN wget -q https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz \
    && tar -xJf ffmpeg-${FFMPEG_VERSION}.tar.xz \
    && mv ffmpeg-${FFMPEG_VERSION} /src/ffmpeg \
    && rm ffmpeg-${FFMPEG_VERSION}.tar.xz

WORKDIR /src/ffmpeg
# --enable-nonfree (required for libfdk-aac) makes the resulting binaries non-redistributable.
# On configure failure, print the end of ffbuild/config.log (the failing test and its linker output).
RUN ./configure \
        --prefix=/opt/ffmpeg \
        --pkg-config-flags="--static" \
        --extra-version="${FFMPEG_EXTRA_VERSION}" \
        --disable-debug \
        --disable-doc \
        --disable-ffplay \
        --enable-alsa \
        $( [ -n "$DECKLINK_SDK_VERSION" ] && echo --enable-decklink ) \
        --enable-gpl \
        --enable-libaom \
        --enable-libfdk-aac \
        --enable-libfontconfig \
        --enable-libfreetype \
        --enable-libharfbuzz \
        --enable-libjack \
        --enable-libopus \
        --enable-libpulse \
        --enable-librist \
        --enable-libsrt \
        --enable-libsvtav1 \
        --enable-libvpx \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libzimg \
        --enable-nonfree \
        --enable-openssl \
        --extra-libs='-lm' \
    || { echo "---- ffbuild/config.log (tail) ----"; tail -n 30 ffbuild/config.log; exit 1; } \
    && make -j"$(nproc)" \
    && make install \
    && make clean

# ---- Verify: device, protocol, muxer and encoder support present; ffmpeg and ffprobe do not link FFmpeg libraries dynamically ----
ARG CHECK_DEVICES="alsa pulse jack" CHECK_PROTOCOLS="srt dtls rist" CHECK_MUXERS="whip" CHECK_ENCODERS="libx264 libx265 libsvtav1 libaom-av1 libfdk_aac libopus libvpx-vp9"
RUN for d in $CHECK_DEVICES; do \
        /opt/ffmpeg/bin/ffmpeg -hide_banner -devices | grep -qw "$d" || { echo "missing device: $d"; exit 1; }; \
    done \
    && for p in $CHECK_PROTOCOLS; do \
        /opt/ffmpeg/bin/ffmpeg -hide_banner -protocols | grep -qw "$p" || { echo "missing protocol: $p"; exit 1; }; \
    done \
    && for m in $CHECK_MUXERS; do \
        /opt/ffmpeg/bin/ffmpeg -hide_banner -muxers | grep -qw "$m" || { echo "missing muxer: $m"; exit 1; }; \
    done \
    && for e in $CHECK_ENCODERS; do \
        /opt/ffmpeg/bin/ffmpeg -hide_banner -encoders | grep -qw "$e" || { echo "missing encoder: $e"; exit 1; }; \
    done \
    && ! ldd /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/bin/ffprobe | grep -qi 'libav' \
    && mkdir -p /out/bin \
    && cp /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/bin/ffprobe /out/bin/

# ---------- Export stage: only ffmpeg and ffprobe, written to the host with --output ----------
FROM scratch AS dist
COPY --from=build /out/ /

# ---------- Runtime stage: ffmpeg and ffprobe plus the system libraries they need ----------
FROM debian:${DEBIAN_VERSION}-slim AS runtime
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libssl3 libstdc++6 libfreetype6 libfontconfig1 libharfbuzz0b libnuma1 \
        libasound2 libpulse0 libjack-jackd2-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/bin /opt/ffmpeg/bin
ENV PATH=/opt/ffmpeg/bin:$PATH

WORKDIR /data
ENTRYPOINT ["ffmpeg"]
