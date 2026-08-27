package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExpandTemplate(t *testing.T) {
	got := expandTemplate(
		"https://example.com/{short_version}/pkg-{version}.tar.xz",
		"1.56.3",
		"",
	)
	want := "https://example.com/1.56/pkg-1.56.3.tar.xz"
	if got != want {
		t.Fatalf("expandTemplate = %q, want %q", got, want)
	}
	got = expandTemplate(
		"https://example.com/lcms2.{version_minor}/lcms2-{version}.tar.gz",
		"2.19.1",
		"",
	)
	want = "https://example.com/lcms2.19.1/lcms2-2.19.1.tar.gz"
	if got != want {
		t.Fatalf("lcms expand = %q, want %q", got, want)
	}
}

func TestReleaseGateInDecode(t *testing.T) {
	cases := []struct {
		gate, ver string
		want      bool
	}{
		{"always", "9.0.1", true},
		{"decode_skip", "9.0.1", false},
		{"needs_libwebp", "9.0.1", false},
		{"needs_libwebp", "8.1.1", true},
		{"needs_libvpl_build", "6.1.3", true},
		{"needs_libvpl_build", "5.1.6", false},
		{"needs_modern_codecs_build", "9.0.1", false},
		{"needs_libaom", "9.0.1", false},
	}
	for _, tc := range cases {
		if got := releaseGateInDecode(tc.gate, tc.ver); got != tc.want {
			t.Errorf("releaseGateInDecode(%q, %q) = %v, want %v", tc.gate, tc.ver, got, tc.want)
		}
	}
}

func TestLoadCatalogAndRead(t *testing.T) {
	cat, err := loadCatalog(sourcesPath())
	if err != nil {
		t.Fatalf("loadCatalog: %v", err)
	}
	if cat.Release.FFmpegVersion == "" {
		t.Fatal("empty ffmpeg version")
	}
	ffmpeg := findSource(cat, "ffmpeg")
	if ffmpeg == nil || ffmpeg.Version != cat.Release.FFmpegVersion {
		t.Fatalf("ffmpeg source mismatch: %+v vs %s", ffmpeg, cat.Release.FFmpegVersion)
	}
	t.Setenv("FFMPEG_VERSION", "")
	if resolveFFmpegVersion(cat) != cat.Release.FFmpegVersion {
		t.Fatal("resolve without env failed")
	}
	t.Setenv("FFMPEG_VERSION", "8.1.2")
	if resolveFFmpegVersion(cat) != "8.1.2" {
		t.Fatal("env override failed")
	}
}

func TestFetchScriptContainsFFmpeg(t *testing.T) {
	cat, err := loadCatalog(sourcesPath())
	if err != nil {
		t.Fatal(err)
	}
	url := ""
	for _, s := range cat.Sources {
		if s.ID == "ffmpeg" {
			url = expandTemplate(s.Fetch.URL, s.Version, s.Commit)
		}
	}
	if !strings.Contains(url, "ffmpeg-"+cat.Release.FFmpegVersion) {
		t.Fatalf("unexpected ffmpeg url %q", url)
	}
}

func TestSaveCatalogRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sources.json")
	src, err := os.ReadFile(sourcesPath())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, src, 0o644); err != nil {
		t.Fatal(err)
	}
	cat, err := loadCatalog(path)
	if err != nil {
		t.Fatal(err)
	}
	orig := cat.Release.FFmpegVersion
	cat.Release.FFmpegVersion = "9.9.9"
	if err := saveCatalog(path, cat); err != nil {
		t.Fatal(err)
	}
	again, err := loadCatalog(path)
	if err != nil {
		t.Fatal(err)
	}
	if again.Release.FFmpegVersion != "9.9.9" {
		t.Fatalf("got %s", again.Release.FFmpegVersion)
	}
	if _, err := os.Stat(path + ".bak"); err != nil {
		t.Fatal("expected backup")
	}
	_ = orig
}

func TestValidFFmpegVersion(t *testing.T) {
	if !validFFmpegVersion("9.0.1") || !validFFmpegVersion("6.1") {
		t.Fatal("expected valid versions")
	}
	if validFFmpegVersion("v9.0.1") || validFFmpegVersion("9") || validFFmpegVersion("9.0.1.2") {
		t.Fatal("expected invalid versions")
	}
	if releaseGateInDecode("needs_libwebp", "v9.0.1") {
		t.Fatal("malformed version must not enable libwebp gate")
	}
}

func TestKnownReleaseGates(t *testing.T) {
	if !isKnownReleaseGate("decode_skip") || isKnownReleaseGate("decode_skipp") {
		t.Fatal("release gate validation mismatch")
	}
}

func TestTrimVersionTagPrefixesLCMS(t *testing.T) {
	got := trimVersionTagPrefixes("lcms2.2.16")
	if got != "2.16" {
		t.Fatalf("got %q", got)
	}
}

func TestResolveOutputPath(t *testing.T) {
	root := repoRoot()
	got := resolveOutputPath("release-notes.md")
	want := filepath.Join(root, "release-notes.md")
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
	if resolveOutputPath("/tmp/out.md") != "/tmp/out.md" {
		t.Fatal("absolute path should be unchanged")
	}
}

func TestIsNewerVersion(t *testing.T) {
	if !isNewerVersion("1.0.0", "1.0.1") {
		t.Fatal("expected 1.0.1 newer")
	}
	if isNewerVersion("2.0.0", "1.9.9") {
		t.Fatal("expected 2.0.0 not older")
	}
}

func TestBumpConfigJSONKeyOrder(t *testing.T) {
	b := BumpConfig{
		Method:    "commit",
		Repo:      "gitrefs:https://github.com/example/libgsm.git",
		Branch:    "master",
		TagFilter: "re:#^refs/heads/master$#|@commit",
	}
	data, err := json.MarshalIndent(b, "  ", "  ")
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	wantOrder := []string{"method", "repo", "branch", "tag_filter"}
	last := -1
	for _, key := range wantOrder {
		idx := strings.Index(got, `"`+key+`"`)
		if idx < 0 {
			t.Fatalf("missing key %q in %s", key, got)
		}
		if idx <= last {
			t.Fatalf("key %q out of order in %s", key, got)
		}
		last = idx
	}
}

func TestCatalogBumpRoundTripStable(t *testing.T) {
	cat, err := loadCatalog(sourcesPath())
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.MarshalIndent(cat, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	var again Catalog
	if err := json.Unmarshal(data, &again); err != nil {
		t.Fatal(err)
	}
	data2, err := json.MarshalIndent(&again, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != string(data2) {
		t.Fatal("catalog JSON not stable across marshal round-trip")
	}
}

func TestParseAPKIndex(t *testing.T) {
	fixture := "" +
		"C:Q1abc\nP:opus-dev\nV:1.5.2-r1\nA:x86_64\n\n" +
		"C:Q1def\nP:rav1e-dev\nV:0.7.1-r0\nA:x86_64\n"
	got := parseAPKIndex([]byte(fixture))
	if got["opus-dev"] != "1.5.2-r1" {
		t.Fatalf("opus-dev = %q", got["opus-dev"])
	}
	if got["rav1e-dev"] != "0.7.1-r0" {
		t.Fatalf("rav1e-dev = %q", got["rav1e-dev"])
	}
}

func TestReleaseVersionLabelAlpine(t *testing.T) {
	alpineVers := map[string]string{
		"opus-dev": "1.5.2-r1",
	}
	s := Source{
		ID: "opus",
		Fetch: &FetchConfig{
			Method:  "alpine",
			Package: "opus-dev",
		},
	}
	got := releaseVersionLabel(s, "alpine:3.22", alpineVers)
	want := "1.5.2-r1 (alpine:3.22)"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestReleaseVersionLabelArchive(t *testing.T) {
	s := Source{
		ID:      "dav1d",
		Version: "1.5.1",
		Fetch:   &FetchConfig{Method: "archive"},
	}
	got := releaseVersionLabel(s, "alpine:3.22", nil)
	if got != "1.5.1" {
		t.Fatalf("got %q", got)
	}
}

func TestDecodeBuildEmoji(t *testing.T) {
	if decodeBuildEmoji(true) != "✅" {
		t.Fatal("expected checkmark")
	}
	if decodeBuildEmoji(false) != "❌" {
		t.Fatal("expected cross")
	}
}

func TestReleaseBodyFormat(t *testing.T) {
	cat, err := loadCatalog(sourcesPath())
	if err != nil {
		t.Fatal(err)
	}
	alpineVers := map[string]string{
		"rav1e-dev":       "0.7.1-r0",
		"opus-dev":        "1.5.2-r1",
		"vo-amrwbenc-dev": "0.1.3-r6",
	}
	ffmpegVer := cat.Release.FFmpegVersion
	var b strings.Builder
	b.WriteString("| Component | Version | In decode build |\n")
	for _, s := range cat.Sources {
		if s.Release == nil {
			continue
		}
		version := releaseVersionLabel(s, cat.Build.AlpineImage, alpineVers)
		inDecode := decodeBuildEmoji(releaseGateInDecode(s.Release.Gate, ffmpegVer))
		b.WriteString(fmt.Sprintf("| %s | %s | %s |\n", s.Name, version, inDecode))
	}
	out := b.String()
	if strings.Contains(out, "Commit") {
		t.Fatal("release table should not include Commit column")
	}
	if !strings.Contains(out, "✅") || !strings.Contains(out, "❌") {
		t.Fatal("release table should use decode emojis")
	}
	if !strings.Contains(out, "1.5.2-r1 (alpine:3.22)") {
		t.Fatal("expected resolved alpine version label")
	}
}
