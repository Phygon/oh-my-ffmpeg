# syntax=docker/dockerfile:1
ARG DEBIAN_VERSION=bookworm

# ---------- Base stage: build tools, apt packages and the fetch helper ----------
FROM debian:${DEBIAN_VERSION}-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget xz-utils build-essential cmake pkg-config nasm yasm \
        autoconf automake libtool meson ninja-build \
        tclsh zlib1g-dev libssl-dev libfreetype6-dev libfontconfig-dev libharfbuzz-dev \
        libnuma-dev \
        libasound2-dev libpulse-dev libjack-jackd2-dev \
        libvulkan-dev git python3 \
    && rm -rf /var/lib/apt/lists/*

# Helper: download, extract and remove the archive
COPY fetch-src.sh /usr/local/bin/fetch-src
RUN chmod 755 /usr/local/bin/fetch-src

WORKDIR /src

# ---- x264: static library (H.264 encoder) ----
FROM base AS x264
ARG X264_REF=27d83708
RUN fetch-src https://code.videolan.org/videolan/x264/-/archive/${X264_REF}/x264-${X264_REF}.tar.bz2 x264.tar.bz2 /src/x264 \
    && cd /src/x264 \
    && ./configure --prefix=/usr/local --enable-static --disable-shared --disable-cli \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/x264

# ---- x265: static library (HEVC encoder) ----
FROM base AS x265
ARG X265_VERSION=4.3
RUN fetch-src https://github.com/Multicorewareinc/x265/archive/refs/tags/${X265_VERSION}.tar.gz x265.tar.gz /src/x265 \
    && cmake -S /src/x265/source -B /src/x265-build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
    && cmake --build /src/x265-build -j"$(nproc)" \
    && cmake --install /src/x265-build \
    && rm -rf /src/x265-build /src/x265

# ---- SVT-AV1: static library (AV1 encoder) ----
FROM base AS svtav1
ARG SVTAV1_VERSION=4.3.0
RUN fetch-src https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v${SVTAV1_VERSION}/SVT-AV1-v${SVTAV1_VERSION}.tar.gz svtav1.tar.gz /src/svt-av1 \
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
FROM base AS libaom
ARG LIBAOM_VERSION=3.15.3
RUN fetch-src https://storage.googleapis.com/aom-releases/libaom-${LIBAOM_VERSION}.tar.gz libaom.tar.gz /src/libaom \
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
FROM base AS libvpx
ARG LIBVPX_VERSION=1.17.0
RUN fetch-src https://github.com/webmproject/libvpx/archive/refs/tags/v${LIBVPX_VERSION}.tar.gz libvpx.tar.gz /src/libvpx \
    && cd /src/libvpx \
    && ./configure --prefix=/usr/local --enable-vp8 --enable-vp9 --disable-examples --disable-tools --disable-docs --disable-unit-tests \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/libvpx

# ---- fdk-AAC: static library (AAC encoder, non-redistributable) ----
FROM base AS fdkaac
ARG FDKAAC_VERSION=3.0.0
RUN fetch-src https://github.com/mstorsjo/fdk-aac/archive/refs/tags/v${FDKAAC_VERSION}.tar.gz fdk-aac.tar.gz /src/fdk-aac \
    && cd /src/fdk-aac \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local --disable-shared --enable-static \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/fdk-aac

# ---- Opus: static library (audio codec) ----
FROM base AS opus
ARG OPUS_VERSION=1.6.1
RUN fetch-src https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz opus.tar.gz /src/opus \
    && cd /src/opus \
    && ./configure --prefix=/usr/local --disable-shared --enable-static --disable-doc --disable-extra-programs \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/opus

# ---- librist: static library (RIST protocol) ----
FROM base AS librist
ARG LIBRIST_VERSION=0.2.20
RUN fetch-src https://code.videolan.org/rist/librist/-/archive/v${LIBRIST_VERSION}/librist-v${LIBRIST_VERSION}.tar.gz librist.tar.gz /src/librist \
    && meson setup /src/librist-build /src/librist --prefix=/usr/local --libdir=lib --default-library=static \
    && meson compile -C /src/librist-build -j"$(nproc)" \
    && meson install -C /src/librist-build \
    && rm -rf /src/librist-build

# ---- libsrt: static library (SRT protocol) ----
FROM base AS srt
ARG SRT_VERSION=1.5.7
RUN fetch-src https://github.com/Haivision/srt/archive/refs/tags/v${SRT_VERSION}.tar.gz srt.tar.gz /src/srt \
    && cmake -S /src/srt -B /src/srt-build \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON \
        -DENABLE_APPS=OFF \
    && cmake --build /src/srt-build -j"$(nproc)" \
    && cmake --install /src/srt-build \
    && rm -rf /src/srt-build /src/srt

# ---- zimg: static library (zscale filter) ----
FROM base AS zimg
ARG ZIMG_VERSION=3.0.6
RUN fetch-src https://github.com/sekrit-twc/zimg/archive/refs/tags/release-${ZIMG_VERSION}.tar.gz zimg.tar.gz /src/zimg \
    && cd /src/zimg \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local --enable-static --disable-shared --disable-testapp \
    && make -j"$(nproc)" \
    && make install \
    && cd /src && rm -rf /src/zimg

# ---- shaderc (glslc): pinned, newer than Debian's (needs the Vulkan 1.4 target env) ----
# Built from the tagged repo: git-sync-deps fetches the matching glslang and SPIRV-Tools.
FROM base AS shaderc
ARG SHADERC_VERSION=2026.4
RUN git clone --depth 1 --branch v${SHADERC_VERSION} https://github.com/google/shaderc /src/shaderc \
    && cd /src/shaderc && python3 utils/git-sync-deps \
    && cmake -S /src/shaderc -B /src/shaderc-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_SHARED_LIBS=OFF \
        -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    && cmake --build /src/shaderc-build -j"$(nproc)" \
    && cmake --install /src/shaderc-build \
    && rm -rf /src/shaderc /src/shaderc-build

# ---- Vulkan-Headers: pinned, newer than Debian's ----
FROM base AS vulkan-headers
ARG VULKAN_HEADERS_VERSION=1.4.369
RUN fetch-src https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v${VULKAN_HEADERS_VERSION}.tar.gz vk-headers.tar.gz /src/vulkan-headers \
    && cmake -S /src/vulkan-headers -B /src/vulkan-headers-build -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --install /src/vulkan-headers-build \
    && rm -rf /src/vulkan-headers-build /src/vulkan-headers

# ---- SPIRV-Headers: pinned, newer than Debian's (needed by libswscale Vulkan code) ----
FROM base AS spirv-headers
ARG SPIRV_HEADERS_VERSION=1.202609.0
RUN fetch-src https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/v${SPIRV_HEADERS_VERSION}.tar.gz spirv-headers.tar.gz /src/spirv-headers \
    && cmake -S /src/spirv-headers -B /src/spirv-headers-build -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --install /src/spirv-headers-build \
    && rm -rf /src/spirv-headers-build /src/spirv-headers

# ---- Libs: merge every library and header into one prefix ----
FROM base AS libs
COPY --from=x264 /usr/local/ /usr/local/
COPY --from=x265 /usr/local/ /usr/local/
COPY --from=svtav1 /usr/local/ /usr/local/
COPY --from=libaom /usr/local/ /usr/local/
COPY --from=libvpx /usr/local/ /usr/local/
COPY --from=fdkaac /usr/local/ /usr/local/
COPY --from=opus /usr/local/ /usr/local/
COPY --from=librist /usr/local/ /usr/local/
COPY --from=srt /usr/local/ /usr/local/
COPY --from=zimg /usr/local/ /usr/local/
COPY --from=shaderc /usr/local/ /usr/local/
COPY --from=vulkan-headers /usr/local/ /usr/local/
COPY --from=spirv-headers /usr/local/ /usr/local/

# ---- FFmpeg source ----
FROM libs AS build
ARG FFMPEG_VERSION=9.1 FFMPEG_EXTRA_VERSION=custom1 DECKLINK_SDK_VERSION=
RUN fetch-src https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz ffmpeg.tar.xz /src/ffmpeg

# ---- FFmpeg configure, build, install and verify ----
# DeckLink headers: bind-mounted at build time only, never in dist/ or the runtime image.
# An empty DECKLINK_SDK_VERSION mounts the placeholder folder, which has no headers.
WORKDIR /src/ffmpeg
# --enable-nonfree makes the binaries non-redistributable.
RUN --mount=type=bind,source=blackmagic_${DECKLINK_SDK_VERSION:-none}/include,target=/opt/decklink \
    export CPATH=/opt/decklink CPLUS_INCLUDE_PATH=/opt/decklink \
    && ./configure \
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
        --enable-libfdk-xhe-aac \
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
        --enable-vulkan \
        --glslc=/usr/local/bin/glslc \
        --extra-libs='-lm' \
    || { echo "---- ffbuild/config.log (tail) ----"; tail -n 30 ffbuild/config.log; exit 1; } \
    && make -j"$(nproc)" \
    && make install \
    && make clean

# ---- Verify: required devices, protocols, muxers, encoders and hwaccels; no dynamic FFmpeg libraries ----
ARG CHECK_DEVICES="alsa pulse jack" \
    CHECK_PROTOCOLS="srt dtls rist" \
    CHECK_MUXERS="whip" \
    CHECK_ENCODERS="libx264 libx265 libsvtav1 libaom-av1 libfdk_aac libfdk_xhe_aac libopus libvpx-vp9" \
    CHECK_HWACCELS="vulkan" \
    CHECK_FILTERS="scale_vulkan overlay_vulkan avgblur_vulkan gblur_vulkan"
RUN devices=$(/opt/ffmpeg/bin/ffmpeg -hide_banner -devices) \
    && protocols=$(/opt/ffmpeg/bin/ffmpeg -hide_banner -protocols) \
    && muxers=$(/opt/ffmpeg/bin/ffmpeg -hide_banner -muxers) \
    && encoders=$(/opt/ffmpeg/bin/ffmpeg -hide_banner -encoders) \
    && hwaccels=$(/opt/ffmpeg/bin/ffmpeg -hide_banner -hwaccels) \
    && filters=$(/opt/ffmpeg/bin/ffmpeg -hide_banner -filters) \
    && for d in $CHECK_DEVICES; do \
        echo "$devices" | grep -qw "$d" || { echo "missing device: $d"; exit 1; }; \
    done \
    && for p in $CHECK_PROTOCOLS; do \
        echo "$protocols" | grep -qw "$p" || { echo "missing protocol: $p"; exit 1; }; \
    done \
    && for m in $CHECK_MUXERS; do \
        echo "$muxers" | grep -qw "$m" || { echo "missing muxer: $m"; exit 1; }; \
    done \
    && for e in $CHECK_ENCODERS; do \
        echo "$encoders" | grep -qw "$e" || { echo "missing encoder: $e"; exit 1; }; \
    done \
    && for h in $CHECK_HWACCELS; do \
        echo "$hwaccels" | grep -qw "$h" || { echo "missing hwaccel: $h"; exit 1; }; \
    done \
    && for f in $CHECK_FILTERS; do \
        echo "$filters" | grep -qw "$f" || { echo "missing filter: $f"; exit 1; }; \
    done \
    && ! ldd /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/bin/ffprobe | grep -qi 'libav' \
    && mkdir -p /out/bin \
    && cp /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/bin/ffprobe /out/bin/

# ---------- Export: ffmpeg and ffprobe only (for --output) ----------
FROM scratch AS dist
COPY --from=build /out/ /

# ---------- Runtime: ffmpeg, ffprobe and their system libraries ----------
FROM debian:${DEBIAN_VERSION}-slim AS runtime
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libssl3 libstdc++6 libfreetype6 libfontconfig1 libharfbuzz0b libnuma1 \
        libasound2 libpulse0 libjack-jackd2-0 libvulkan1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/bin /opt/ffmpeg/bin
ENV PATH=/opt/ffmpeg/bin:$PATH

WORKDIR /data
ENTRYPOINT ["ffmpeg"]
