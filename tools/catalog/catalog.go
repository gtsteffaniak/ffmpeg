package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const defaultSourcesPath = "sources.json"

// Catalog is the root of sources.json.
type Catalog struct {
	Release ReleaseConfig `json:"release"`
	Build   BuildConfig   `json:"build"`
	Sources []Source      `json:"sources"`
}

type ReleaseConfig struct {
	FFmpegVersion     string `json:"ffmpeg_version"`
	MarkGitHubLatest  bool   `json:"mark_github_latest"`
}

type BuildConfig struct {
	AlpineImage    string `json:"alpine_image"`
	ApkRepository  string `json:"apk_repository,omitempty"`
}

type Source struct {
	ID      string       `json:"id"`
	Name    string       `json:"name"`
	Enabled bool         `json:"enabled"`
	Version string       `json:"version,omitempty"`
	Commit  string       `json:"commit,omitempty"`
	Fetch   *FetchConfig `json:"fetch,omitempty"`
	Release *ReleaseMeta `json:"release,omitempty"`
	Bump    *BumpConfig  `json:"bump,omitempty"`
}

type FetchConfig struct {
	Method  string `json:"method"`
	URL     string `json:"url,omitempty"`
	Dir     string `json:"dir,omitempty"`
	Gate    string `json:"gate,omitempty"`
	Post    string `json:"post,omitempty"`
	Package string `json:"package,omitempty"`
}

type ReleaseMeta struct {
	Gate string `json:"gate"`
}

type BumpConfig struct {
	Repo      string `json:"repo"`
	TagFilter string `json:"tag_filter,omitempty"`
	Method    string `json:"method,omitempty"`
	Branch    string `json:"branch,omitempty"`
}

func sourcesPath() string {
	if p := os.Getenv("SOURCES_JSON"); p != "" {
		if filepath.IsAbs(p) {
			return p
		}
		return filepath.Join(repoRoot(), p)
	}
	return filepath.Join(repoRoot(), defaultSourcesPath)
}

func loadCatalog(path string) (*Catalog, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var c Catalog
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &c, nil
}

func saveCatalog(path string, c *Catalog) error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	backup := path + ".bak"
	_ = os.Rename(path, backup)
	return os.WriteFile(path, data, 0o644)
}

func expandTemplate(tmpl, version, commit string) string {
	if tmpl == "" {
		return ""
	}
	short := version
	if parts := strings.Split(version, "."); len(parts) >= 2 {
		short = parts[0] + "." + parts[1]
	}
	versionNoprefix2 := strings.TrimPrefix(version, "2.")
	r := strings.NewReplacer(
		"{version}", version,
		"{short_version}", short,
		"{version_minor}", versionNoprefix2,
		"{commit}", commit,
	)
	return r.Replace(tmpl)
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func findSource(c *Catalog, id string) *Source {
	for i := range c.Sources {
		if c.Sources[i].ID == id {
			return &c.Sources[i]
		}
	}
	return nil
}

func resolveFFmpegVersion(c *Catalog) string {
	if v := os.Getenv("FFMPEG_VERSION"); v != "" {
		return v
	}
	return c.Release.FFmpegVersion
}

func repoRoot() string {
	if root := os.Getenv("FFMPEG_ROOT"); root != "" {
		return root
	}
	wd, err := os.Getwd()
	if err != nil {
		return "."
	}
	dir := wd
	for {
		if _, err := os.Stat(filepath.Join(dir, defaultSourcesPath)); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return wd
		}
		dir = parent
	}
}

func dockerfilePaths() []string {
	root := repoRoot()
	candidates := []string{
		filepath.Join(root, "docker", "dockerfile.monolithic"),
		filepath.Join(root, "docker", "dockerfile.final"),
		filepath.Join(root, "docker", "dockerfile.av1"),
		filepath.Join(root, "docker", "dockerfile.audio"),
		filepath.Join(root, "docker", "dockerfile.image-formats"),
		filepath.Join(root, "docker", "dockerfile.modern-codecs"),
		filepath.Join(root, "docker", "dockerfile.vaapi"),
		filepath.Join(root, "docker", "dockerfile.vpx-avs"),
	}
	var out []string
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			out = append(out, p)
		}
	}
	return out
}
