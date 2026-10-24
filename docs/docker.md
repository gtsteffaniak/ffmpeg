# Running GPU-accelerated FFmpeg (full glibc image)

The **full** image (`gtstef/ffmpeg:<version>`) is built on **Debian 11 (bullseye)** so binaries run on any glibc 2.31+ host with matching runtime packages. Codec libraries are linked statically; **libva**, **libvpl**, **Vulkan**, **OpenCL**, and **NVIDIA** user-space drivers are loaded dynamically (`dlopen`).

The **static** image (`gtstef/ffmpeg:<version>-static`) is a musl binary on `scratch` with **no GPU** support (V4L2 M2M on arm64 only). Use it for portable software transcoding.

## Base image and glibc compatibility

The **full / GPU** Linux image is built and run on **Debian 11 (bullseye)** — not bookworm or Ubuntu — by design.

**Why Debian 11**

- **glibc 2.31** is the compatibility floor for the **extracted** `ffmpeg` / `ffprobe` tarballs (`ffmpeg-<version>-linux-<arch>.tar.gz`). A dynamically linked glibc binary needs **host glibc ≥ build glibc**. Bullseye targets a wide set of still-supported hosts, for example:
  - Ubuntu **20.04** and newer
  - Debian **11** and newer
  - RHEL / Rocky / Alma **9** and newer
- Bullseye is the oldest still-supported Debian release with a practical **libva / libvpl / non-free Intel VA** stack for the full image.

**Running inside Docker**

- The **host Linux distribution does not need to match** Debian 11. Containers use the image’s userspace; the host only supplies the **kernel**, **device nodes** (`/dev/dri`, `/dev/dxg`, …), and optional **GPU injection**.
- **NVIDIA NVENC/CUDA**: the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) mounts **host** driver libraries into the container. Those libraries are built for recent distros and work with FFmpeg in this image as long as the toolkit and driver are current.

**Trade-off: older in-image GPU userspace**

- Runtime packages in the image (Mesa VA, `intel-media-va-driver-non-free`, libvpl, etc.) come from **bullseye**. That keeps glibc compatibility predictable but means **very new GPUs** (recent Intel Arc generations, newest AMD VA paths) may need **newer VA/Mesa drivers** than bullseye ships. If VAAPI fails on bleeding-edge hardware, try a newer host driver stack, a newer distro runtime, or software encode via the **static** image.

**WSL exception (bookworm Mesa file only)**

- WSL2 VAAPI uses Mesa’s **`d3d12_drv_video.so`**, which bullseye’s `mesa-va-drivers` does not include. The image installs that driver from **Debian 12 (bookworm)** via [`scripts/install-mesa-d3d12-va.sh`](../scripts/install-mesa-d3d12-va.sh) (full package or single-file extract). **FFmpeg and glibc remain bullseye-built**; only the d3d12 VA driver blob is newer. Caveat: mixing a bookworm Mesa DRI driver with bullseye `libva` is a narrow, tested exception for WSL — not a general upgrade of in-image Mesa for bare-metal `/dev/dri`.

**Unaffected variants**

- **Windows** releases (mingw-w64 cross-compile) do not use this Debian runtime.
- The **static** Alpine → `scratch` image is musl-based and does not share bullseye glibc or these VA packages.

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

## WSL2 (Docker on Windows / Docker Desktop)

WSL2 exposes the Windows GPU through **`/dev/dxg`** and ships user-mode drivers under **`/usr/lib/wsl/lib`** (CUDA/NVENC, D3D12 interop). The full image bundles **Mesa’s `d3d12_drv_video.so`** VAAPI driver (bookworm Mesa on amd64 when bullseye’s Mesa is too old) so VAAPI works inside the container when you set `LIBVA_DRIVER_NAME=d3d12`.

There is typically **no usable `/dev/dri/renderD128`** in WSL2 for host GPU video — use **`/dev/dxg`** and the d3d12 VA driver instead.

### Host requirements

- **Windows 11**, or **Windows 10 21H2+** with an up-to-date WSL2 kernel (`wsl --update`)
- Current **GPU driver** from the vendor (NVIDIA / AMD / Intel)
- WSL2 distro (Ubuntu/Debian recommended) with `/dev/dxg` present: `ls -l /dev/dxg`
- For **NVENC inside Docker Desktop**: enable GPU in Docker Desktop settings and pass **`--gpus all`**

### Run (VAAPI via D3D12)

```bash
docker run --rm -it \
  --device /dev/dxg \
  -v /usr/lib/wsl:/usr/lib/wsl:ro \
  -e LIBVA_DRIVER_NAME=d3d12 \
  -e LIBVA_DRIVERS_PATH=/usr/lib/wsl/lib:/usr/lib/x86_64-linux-gnu/dri \
  -e LD_LIBRARY_PATH=/usr/lib/wsl/lib \
  gtstef/ffmpeg:9.0.2 \
  -hide_banner -init_hw_device vaapi=va:/dev/dxg \
  -f lavfi -i testsrc=d=2:size=1280x720 \
  -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null -
```

### Run (NVENC / CUDA on WSL)

NVIDIA’s WSL libraries live on the host under `/usr/lib/wsl/lib`. Mount them read-only and add **`--gpus all`** when using Docker Desktop’s NVIDIA integration:

```bash
docker run --rm -it \
  --gpus all \
  --device /dev/dxg \
  -v /usr/lib/wsl:/usr/lib/wsl:ro \
  -e LD_LIBRARY_PATH=/usr/lib/wsl/lib \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
  gtstef/ffmpeg:9.0.2 \
  -hide_banner -f lavfi -i testsrc=d=2:size=1280x720 \
  -c:v h264_nvenc -f null -
```

### Extracted binary (`.tar.gz` from releases)

The glibc **full** tarball is dynamically linked; on WSL2 use the same environment when invoking `ffmpeg`/`ffprobe` from the host or a minimal container:

```bash
export LIBVA_DRIVER_NAME=d3d12
export LIBVA_DRIVERS_PATH=/usr/lib/wsl/lib:/usr/lib/x86_64-linux-gnu/dri
export LD_LIBRARY_PATH=/usr/lib/wsl/lib
./ffmpeg -init_hw_device vaapi=va:/dev/dxg ...
```

Install matching Debian **libva** / **mesa-va-drivers** on the host, or run inside the full Docker image above.

### Verification

```bash
ls -l /dev/dxg /usr/lib/wsl/lib
docker run --rm --entrypoint sh gtstef/ffmpeg:9.0.2 \
  -c 'find /usr/lib -name d3d12_drv_video.so'
ffmpeg -hide_banner -hwaccels
ffmpeg -hide_banner -encoders | grep -E 'vaapi|nvenc'
```

Local checks: `make hwtest` (auto-detects `/dev/dxg` and exercises WSL VAAPI + NVENC when libraries are present).

### Caveats

| Topic | Notes |
|--------|--------|
| No `/dev/dri` | Normal on WSL2; do not assume `renderD128` exists |
| d3d12 encode | Depends on Windows + GPU vendor support for D3D12 video encode |
| Intel iHD in WSL | Often fails against `/dev/dxg`; use **`LIBVA_DRIVER_NAME=d3d12`** |
| ARM WSL | d3d12 VA driver is an **amd64** image concern; use software/static on arm64 |
| Patents / nonfree | NVENC and some VA paths require FFmpeg nonfree encoders |

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
