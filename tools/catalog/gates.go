package main

import (
	"strconv"
	"strings"
)

var knownFetchGates = map[string]struct{}{
	"needs_libwebp":             {},
	"needs_openjpeg":            {},
	"needs_libvpx":              {},
	"needs_libaom":              {},
	"needs_libvorbis":           {},
	"needs_libvpl_build":        {},
	"needs_vaapi_build":         {},
	"needs_v4l2_m2m_build":      {},
	"needs_modern_codecs_build": {},
	"static_skip":               {},
}

var knownReleaseGates = map[string]struct{}{
	"always":                    {},
	"never":                     {},
	"decode_skip":               {},
	"static_skip":               {},
	"needs_libwebp":             {},
	"needs_openjpeg":            {},
	"needs_libvpx":              {},
	"needs_libaom":              {},
	"needs_libvorbis":           {},
	"needs_libvpl_build":        {},
	"needs_vaapi_build":         {},
	"needs_v4l2_m2m_build":      {},
	"needs_modern_codecs_build": {},
}

func isKnownFetchGate(gate string) bool {
	_, ok := knownFetchGates[gate]
	return ok
}

func isKnownReleaseGate(gate string) bool {
	_, ok := knownReleaseGates[gate]
	return ok
}

func validFFmpegVersion(ver string) bool {
	parts := strings.Split(ver, ".")
	if len(parts) < 2 || len(parts) > 3 {
		return false
	}
	for _, p := range parts {
		if p == "" {
			return false
		}
		for _, c := range p {
			if c < '0' || c > '9' {
				return false
			}
		}
	}
	return true
}

func ffmpegVersionGE(ver, min string) bool {
	left, okLeft := versionKey(ver)
	right, okRight := versionKey(min)
	if !okLeft || !okRight {
		return false
	}
	return left >= right
}

func versionKey(ver string) (int, bool) {
	if !validFFmpegVersion(ver) {
		return 0, false
	}
	parts := strings.Split(ver, ".")
	nums := make([]int, 3)
	for i := 0; i < 3 && i < len(parts); i++ {
		n, err := strconv.Atoi(parts[i])
		if err != nil {
			return 0, false
		}
		nums[i] = n
	}
	return nums[0]*1_0000_0000 + nums[1]*1_0000 + nums[2], true
}

// releaseGateInStatic evaluates release.gate for the Alpine static image (BUILD_VARIANT=static).
func releaseGateInStatic(gate, ffmpegVersion string) bool {
	switch gate {
	case "always":
		return true
	case "never", "decode_skip", "static_skip":
		return false
	case "needs_libwebp", "needs_openjpeg", "needs_libvpx", "needs_libaom", "needs_libvorbis":
		return false
	case "needs_libvpl_build", "needs_vaapi_build":
		return false
	case "needs_v4l2_m2m_build":
		return true
	case "needs_modern_codecs_build":
		return false
	default:
		return false
	}
}

// Deprecated alias for release notes migration.
func releaseGateInDecode(gate, ffmpegVersion string) bool {
	return releaseGateInStatic(gate, ffmpegVersion)
}
