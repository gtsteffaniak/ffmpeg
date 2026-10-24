# Filebrowser / go-ffmpeg software capabilities (static image)

Derived from [filebrowser](https://github.com/gtsteffaniak/filebrowser) `main` and PR [#3168](https://github.com/gtsteffaniak/filebrowser/pull/3168) (HLS transcoding via `backend/internal/transcoding/*` and `internal/ffmpeg`), and [go-ffmpeg](https://github.com/gtsteffaniak/go-ffmpeg) `ops/*`, `encode/*`, `probe/*` (v1.5.3+).

The **static** Docker image is sized for **software** paths (`ForceSoftware` / no GPU). Hardware encoders are intentionally absent.

## Video encoders (external)

| Encoder | Used by |
|---------|---------|
| `libx264` | HLS fMP4 transcode (`ops/hls_segment.go`, `hls_vod_job.go`, `hls_continuous.go`), `Transcode`, `FMP4Transcode`, `SegmentRecord`, `TimelapseCompile` |

No other external video encoders are required for filebrowser software mode.

## Audio encoders (native)

| Encoder | Used by |
|---------|---------|
| `aac` | HLS transcode ( `-c:a aac`, `-profile:a aac_low` ), `Transcode`, `FMP4Transcode`, `SegmentRecord`; audio transcode when source is not AAC |

## Image / frame encoders (native)

| Encoder | Used by |
|---------|---------|
| `mjpeg` | `VideoPreview`, `VideoPreviewFrame` (`-vcodec mjpeg -f image2`) |

`Screenshot` uses `-f image2` to a file path (JPEG by extension); previews use MJPEG explicitly.

## Decoders / demuxers (broad)

Keep native FFmpeg decoders plus **libdav1d** (configured in static builds). Typical playback inputs: H.264/HEVC/VP9/AV1/MPEG-4, AAC/MP3/AC3/EAC3/Opus/Vorbis, subtitles (SRT/ASS/…), **HEIC/HEIF** (`ConvertHEIC`), Matroska/MP4/MOV/AVI/WebM, concat demuxer (`TimelapseCompile`).

## Muxers

| Muxer | Used by |
|-------|---------|
| `mp4` / fragmented MP4 | HLS fMP4 (`-f mp4` + `empty_moov+frag_keyframe+default_base_moof`), `FMP4Transcode`, `SegmentRecord` |
| `mpegts` | Legacy `HLSSegment` MPEG-TS path |
| `hls` | `StartHLSContinuous` |
| `image2` | `VideoPreview`, `Screenshot`, `ConvertHEIC` (JPEG output) |
| `webvtt` | `probe.ExtractSubtitle` (`-f webvtt`) |
| `segment` | `SegmentRecord` (`-f segment -segment_format mp4`) |

## Protocols

`file`, `http`, `https`, `tcp`, `rtsp` (and `hls` when reading HLS inputs) — see `capabilities.KnownProtocols` and `appendInputFlags` / protocol whitelist in go-ffmpeg.

## Video / audio filters

| Filter | Used by |
|--------|---------|
| `scale` | Previews (`PreviewScaleFilter`), HLS transcode, `ConvertHEIC`, `FMP4Transcode`, `TimelapseCompile` |
| `crop` | Preview fill mode (`ScaleFill`) |
| `format` | HLS / software encode (`yuv420p`, `nv12` paths) |
| `transpose`, `hflip`, `vflip` | `ConvertHEIC` / orientation (`ConvertHEICOptions.OrientationFilter`) |
| `aresample` | HLS audio (`-af aresample=async=1[:first_pts=0]`) |
| `fps` | `TimelapseCompile` |
| `concat` | `TimelapseCompile` demuxer + filter graph |
| `segment` | `SegmentRecord` |
| `tile` | Registered requirement for `ConvertHEIC` (tile-grid HEIC) |

## Bitstream filters

| BSF | Used by |
|-----|---------|
| `aac_adtstoasc` | HLS video-copy / audio transcode to fMP4 (`hls_segment.go`, `hls_vod_job.go`, `hls_continuous.go`) |

## Libraries linked in static Alpine build

- **libx264** (only external video encoder)
- **libdav1d**, **libass**, fontconfig/freetype/harfbuzz stack (subtitles / ASS)
- **GnuTLS** (HTTPS)
- No libva/libvpl/GPU userspace

`go-ffmpeg` treats `--enable-libx264` in `ffmpeg -version` configuration as a **full** software encode profile (`capabilities.InferBuildProfile`).
