package main

import (
	"strconv"
	"strings"
)

func ffmpegVersionGE(ver, min string) bool {
	return versionKey(ver) >= versionKey(min)
}

func versionKey(ver string) int {
	parts := strings.Split(ver, ".")
	nums := make([]int, 3)
	for i := 0; i < 3 && i < len(parts); i++ {
		n, _ := strconv.Atoi(parts[i])
		nums[i] = n
	}
	return nums[0]*1_0000_0000 + nums[1]*1_0000 + nums[2]
}

// releaseGateInDecode evaluates release.gate for the decode-only image (DECODE_ONLY=true).
func releaseGateInDecode(gate, ffmpegVersion string) bool {
	switch gate {
	case "always":
		return true
	case "never", "decode_skip":
		return false
	case "needs_libwebp":
		return !ffmpegVersionGE(ffmpegVersion, "9.0.0")
	case "needs_openjpeg", "needs_libvpx", "needs_libaom", "needs_libvorbis":
		return false
	case "needs_libvpl_build":
		return ffmpegVersionGE(ffmpegVersion, "6.0.0")
	case "needs_modern_codecs_build":
		return false
	default:
		return false
	}
}
