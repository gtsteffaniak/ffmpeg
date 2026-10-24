# Running GPU-accelerated FFmpeg (full glibc image)

The **full** image (`gtstef/ffmpeg:<version>`) is built on **Debian 11 (bullseye)** so binaries run on any glibc 2.31+ host with matching runtime packages. Codec libraries are linked statically; **libva**, **libvpl**, **Vulkan**, **OpenCL**, and **NVIDIA** user-space drivers are loaded dynamically (`dlopen`).

The **static** image (`gtstef/ffmpeg:<version>-static`) is a musl binary on `scratch` with **no GPU** support (V4L2 M2M on arm64 only). Use it for portable software transcoding.

## Intel (VAAPI / QSV)

**Host:** iGPU or Intel discrete GPU with kernel `i915` / `xe`, `/dev/dri/renderD128`.

```bash
docker run --rm -it \
  --device /dev/dri:/dev/dri \
  --group-add video \
  -e LIBVA_DRIVER_NAME=iHD \
  gtstef/ffmpeg:9.0.2 \
  -hide_banner -init_hw_device vaapi=va:/dev/dri/renderD128 \
  -filter_hw_device va -f lavfi -i testsrc=d=2:size=1280x720 \
  -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null -
```

- **iHD** (default on Gen8+): `intel-media-va-driver-non-free` in the image.
- **i965**: older hardware, set `LIBVA_DRIVER_NAME=i965`.
- **QSV** uses libvpl (`h264_qsv`); ensure `libmfx-gen` / oneVPL runtime matches the host.

Debug: `LIBVA_MESSAGING_LEVEL=2 vainfo` (install `vainfo` on host or exec into container).

## AMD (VAAPI / AMF)

```bash
docker run --rm --device /dev/dri:/dev/dri --group-add video \
  gtstef/ffmpeg:9.0.2 \
  -c:v h264_vaapi ...
```

AMF (`h264_amf`) needs AMD's proprietary AMF runtime on the host; it is not bundled in the image.

## NVIDIA (NVENC / NVDEC)

Requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html):

```bash
docker run --rm --gpus all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
  gtstef/ffmpeg:9.0.2 \
  -hide_banner -c:v h264_nvenc -f lavfi -i testsrc=d=2:size=1280x720 -f null -
```

Driver libraries are injected by the toolkit; the image ships nv-codec-headers at build time only.

## WSL2

Mount GPU paravirtualization:

```bash
docker run --rm -it \
  -v /usr/lib/wsl:/usr/lib/wsl:ro \
  --device /dev/dxg \
  gtstef/ffmpeg:9.0.2 -hwaccels
```

Use D3D12/Vulkan paths when available on your Windows build.

## Raspberry Pi (V4L2 M2M)

On **arm64 static** image only (kernel ioctls, no dlopen):

```bash
docker run --rm --device /dev/video11:/dev/video11 \
  gtstef/ffmpeg:9.0.2-static \
  -c:v h264_v4l2m2m -c:v h264 -f lavfi -i testsrc=d=2 -f null -
```

## Compose example (Intel VAAPI)

```yaml
services:
  ffmpeg:
    image: gtstef/ffmpeg:9.0.2
    devices:
      - /dev/dri:/dev/dri
    group_add:
      - "44"   # render group gid on host — adjust via `getent group render`
    environment:
      LIBVA_DRIVER_NAME: iHD
      LIBVA_MESSAGING_LEVEL: "1"
```

## Verification

```bash
ffmpeg -hide_banner -hwaccels
ffmpeg -hide_banner -encoders | grep -E 'vaapi|nvenc|qsv|amf'
vainfo
ffmpeg -v verbose -init_hw_device vaapi=va:/dev/dri/renderD128
```

## Common errors

| Symptom | Meaning |
|--------|---------|
| `Cannot load libcuda.so` / NVENC init fail | GPU not passed to container or missing `video` capability |
| VAAPI error **-12** (`ENOMEM`) | Often missing render node permissions or static image (no libva drivers) |
| `libva.so.2: cannot open` | Host/runtime mismatch — use full glibc image + Debian bullseye VA drivers |
| Rootless Docker | Map `render` GID; may need `--device /dev/dri/renderD128` |

## Licensing

Linux builds use **GnuTLS** instead of OpenSSL for HTTPS. **GPL v3** codecs (x264, x265, etc.) are enabled. **NVENC/AMF/cuvid** require FFmpeg's `--enable-nonfree` flag; binaries are redistributable under FFmpeg's license terms but some encoder outputs may be patent-restricted in your jurisdiction.
