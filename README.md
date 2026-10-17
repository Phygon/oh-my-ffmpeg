# oh-my-ffmpeg

*Build your own FFmpeg*

FFmpeg 9.0.2 and its codec and protocol libraries (static), built from source on Debian 12 for Docker and Podman.

Extra codecs, devices and protocols included in the build:
- **Audio devices:** ALSA, PulseAudio, JACK
- **Video devices:** Blackmagic DeckLink (requires the Blackmagic SDK files, see Prerequisites)
- **Video codecs:** x264, x265, SVT-AV1, libaom (AV1), libvpx (VP8/VP9)
- **Audio codecs:** fdk-AAC, Opus
- **Filters:** zscale (libzimg) for high-quality scaling and colour conversion
- **Protocols:** SRT, RIST

The build uses `--enable-nonfree` for fdk-AAC. Binaries built this way cannot be redistributed.

## Quickstart (Docker)

The Blackmagic DeckLink SDK is optional. To build with it, see Prerequisites before building.

```bash
docker build -t ffmpeg9 .
docker build --target dist --output type=local,dest=./dist .
docker run --rm ffmpeg9 -version
```

The `dist` build writes `ffmpeg` and `ffprobe` to `./dist/bin/`.

## Prerequisites

- Podman 4.x or later, or Docker.
- Optional, for DeckLink support: the Blackmagic DeckLink SDK headers in a folder next to the Dockerfile, for example `blackmagic_12.2.2/include/`. Pass the version as a build argument, for example `--build-arg DECKLINK_SDK_VERSION=12.2.2 --build-arg CHECK_DEVICES="alsa pulse jack decklink"`.
- On the host, to use DeckLink hardware: the Blackmagic Desktop Video driver. It is not needed to build.

## Build settings

These are build arguments with defaults in the Dockerfile. Override one with `--build-arg`.

| Argument | Default | Purpose |
| --- | --- | --- |
| `FFMPEG_VERSION` | `9.0.2` | FFmpeg release to build |
| `FFMPEG_EXTRA_VERSION` | `1~custom` | Suffix added to the version string |
| `SRT_VERSION` | `1.5.7` | libsrt release to build |
| `ZIMG_VERSION` | `3.0.6` | zimg release to build (zscale filter) |
| `LIBRIST_VERSION` | `0.2.20` | librist release to build (RIST protocol) |
| `X264_REF` | `27d83708` | x264 commit to build (pinned) |
| `X265_VERSION` | `4.2` | x265 release to build |
| `SVTAV1_VERSION` | `4.2.0` | SVT-AV1 release to build |
| `LIBAOM_VERSION` | `3.15.1` | libaom release to build |
| `LIBVPX_VERSION` | `1.17.0` | libvpx release to build |
| `FDKAAC_VERSION` | `2.0.3` | fdk-AAC release to build |
| `OPUS_VERSION` | `1.6.1` | Opus release to build |
| `DECKLINK_SDK_VERSION` | *(empty)* | Set to build with DeckLink support, e.g. `12.2.2` (uses `blackmagic_<version>/include/`) |
| `CHECK_DEVICES` | `alsa pulse jack` | Devices that must be present (add `decklink` for DeckLink builds) |
| `CHECK_PROTOCOLS` | `srt dtls rist` | Protocols that must be present |
| `CHECK_MUXERS` | `whip` | Muxers that must be present |
| `CHECK_ENCODERS` | `libx264 libx265 libsvtav1 libaom-av1 libfdk_aac libopus libvpx-vp9` | Encoders that must be present |

Example:
```bash
podman build --build-arg FFMPEG_EXTRA_VERSION=2~custom -t ffmpeg9 .
```

## 1. Build the runtime image

Docker:
```bash
docker build -t ffmpeg9 .
```

Podman:
```bash
podman build -t ffmpeg9 .
```

## 2. Build the dist folder

Exports only `ffmpeg` and `ffprobe` to `./dist/bin` on the host.

Docker:
```bash
docker build --target dist --output type=local,dest=./dist .
```

Podman:
```bash
podman build --target dist --output type=local,dest=./dist .
```

Run the host binaries:
```bash
./dist/bin/ffmpeg -version
```

FFmpeg is built statically, so the binaries do not need `LD_LIBRARY_PATH`. They do need some system libraries. Check for missing ones with:
```bash
ldd ./dist/bin/ffmpeg | grep "not found"
```

If any are listed, install them on the host, or run FFmpeg from the image in step 3.

## 3. Run FFmpeg from the image

Docker:
```bash
docker run --rm -v "$PWD:/data" ffmpeg9 -i /data/input.mp4 /data/output.mkv
docker run --rm --entrypoint ffprobe ffmpeg9 -v error -show_format /data/input.mp4
```

Podman:
```bash
podman run --rm -v "$PWD:/data:Z" ffmpeg9 -i /data/input.mp4 /data/output.mkv
podman run --rm --entrypoint ffprobe ffmpeg9 -v error -show_format /data/input.mp4
```

The `:Z` suffix is needed on SELinux systems (Fedora, RHEL) so Podman can read and write the mounted folder. It is harmless elsewhere.

## Notes

- Add `dist/` and the DeckLink SDK folder to `.gitignore`. The SDK is proprietary.
- The `dist` target shares the build cache with step 1, so the second build is fast.
- The build fails if any item in the `CHECK_*` lists is missing from the FFmpeg build. The error names the missing item.

## Cleaning up

Rebuilds leave old images behind as dangling `<none>` images. Remove them with:
```bash
podman image prune
```
Add `-a` to remove all images not used by a container. This also removes `ffmpeg9` if no container uses it, and the next build will recompile FFmpeg.
