# syntax=docker/dockerfile:1
ARG DEBIAN_VERSION=bookworm

# ---------- Build stage: compile libsrt (static) and FFmpeg ----------
FROM debian:${DEBIAN_VERSION}-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

# libfdk-aac is in Debian's contrib component, so enable contrib and non-free.
RUN sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget xz-utils build-essential cmake pkg-config nasm yasm \
        autoconf automake libtool meson ninja-build \
        tclsh zlib1g-dev libssl-dev libfreetype6-dev libfontconfig-dev libharfbuzz-dev \
        libopus-dev libvpx-dev libx264-dev libx265-dev libnuma-dev \
        libsvtav1enc-dev libaom-dev libfdk-aac-dev \
        libasound2-dev libpulse-dev libjack-jackd2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

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

RUN sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libssl3 libstdc++6 libfreetype6 libfontconfig1 libharfbuzz0b \
        libopus0 libvpx7 libx264-164 libx265-199 libnuma1 \
        libsvtav1enc1 libaom3 libfdk-aac2 \
        libasound2 libpulse0 libjack-jackd2-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/bin /opt/ffmpeg/bin
ENV PATH=/opt/ffmpeg/bin:$PATH

WORKDIR /data
ENTRYPOINT ["ffmpeg"]
