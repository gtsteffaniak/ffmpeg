package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const defaultApkArch = "x86_64"

func alpinePackageName(s Source) string {
	if s.Fetch != nil && s.Fetch.Package != "" {
		return s.Fetch.Package
	}
	return s.ID + "-dev"
}

func alpineSources(cat *Catalog) []Source {
	var out []Source
	for _, s := range cat.Sources {
		if s.Enabled && s.Fetch != nil && s.Fetch.Method == "alpine" {
			out = append(out, s)
		}
	}
	return out
}

func resolveAlpinePackages(cat *Catalog) (map[string]string, error) {
	sources := alpineSources(cat)
	if len(sources) == 0 {
		return map[string]string{}, nil
	}
	repos, err := alpineIndexRepos(cat)
	if err != nil {
		return nil, err
	}
	versions := map[string]string{}
	for _, repo := range repos {
		indexURL := repo + defaultApkArch + "/APKINDEX.tar.gz"
		index, err := fetchAPKIndex(indexURL)
		if err != nil {
			return nil, fmt.Errorf("fetch APKINDEX from %s: %w", indexURL, err)
		}
		for pkg, ver := range parseAPKIndex(index) {
			versions[pkg] = ver
		}
	}
	out := make(map[string]string, len(sources))
	for _, s := range sources {
		pkg := alpinePackageName(s)
		v, ok := versions[pkg]
		if !ok {
			return nil, fmt.Errorf("alpine package %q not found in configured repositories", pkg)
		}
		out[pkg] = v
	}
	return out, nil
}

func alpineIndexRepos(cat *Catalog) ([]string, error) {
	branch, err := alpineReleaseBranch(cat.Build.AlpineImage)
	if err != nil {
		return nil, err
	}
	base := fmt.Sprintf("https://dl-cdn.alpinelinux.org/alpine/%s/", branch)
	repos := []string{
		base + "main/",
		base + "community/",
	}
	if extra := strings.TrimSpace(cat.Build.ApkRepository); extra != "" {
		if !strings.HasSuffix(extra, "/") {
			extra += "/"
		}
		repos = append(repos, extra)
	}
	return repos, nil
}

func alpineReleaseBranch(image string) (string, error) {
	tag := strings.TrimPrefix(strings.TrimSpace(image), "alpine:")
	if tag == "" || tag == image {
		return "", fmt.Errorf("invalid alpine_image %q", image)
	}
	if tag == "edge" {
		return "edge", nil
	}
	return "v" + tag, nil
}

func fetchAPKIndex(url string) ([]byte, error) {
	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %s", resp.Status)
	}
	gz, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, err
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if hdr.Typeflag == tar.TypeReg && hdr.Name == "APKINDEX" {
			return io.ReadAll(tr)
		}
	}
	return nil, fmt.Errorf("APKINDEX not found in archive")
}

func parseAPKIndex(data []byte) map[string]string {
	versions := map[string]string{}
	for _, block := range bytes.Split(data, []byte("\n\n")) {
		var pkg, ver string
		for _, line := range bytes.Split(block, []byte("\n")) {
			if len(line) < 2 {
				continue
			}
			switch line[0] {
			case 'P':
				pkg = string(line[2:])
			case 'V':
				ver = string(line[2:])
			}
		}
		if pkg != "" && ver != "" {
			versions[pkg] = ver
		}
	}
	return versions
}

func releaseVersionLabel(s Source, alpineImage string, alpineVers map[string]string) string {
	if s.Fetch != nil && s.Fetch.Method == "alpine" {
		ver := s.Version
		if ver == "" {
			pkg := alpinePackageName(s)
			if v, ok := alpineVers[pkg]; ok {
				ver = v
			} else {
				ver = "unknown"
			}
		}
		return fmt.Sprintf("%s (%s)", ver, alpineImage)
	}
	if s.Version != "" {
		return s.Version
	}
	if s.Commit != "" {
		return s.Commit
	}
	return "—"
}

func decodeBuildEmoji(inDecode bool) string {
	if inDecode {
		return "✅"
	}
	return "❌"
}
