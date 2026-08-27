package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
)

type SemanticVersion struct {
	Major int
	Minor int
	Patch int
	Tag   string
}

func (u *UpdateCmd) Run() error {
	path := sourcesPath()
	log.Println("Starting version check for", path)

	cat, err := loadCatalog(path)
	if err != nil {
		return err
	}

	type result struct {
		idx    int
		latest string
		err    error
	}

	var jobs []int
	for i, s := range cat.Sources {
		if s.Enabled && s.Bump != nil {
			jobs = append(jobs, i)
		}
	}

	results := make([]result, len(jobs))
	var wg sync.WaitGroup
	for i, idx := range jobs {
		wg.Add(1)
		go func(ri, srcIdx int) {
			defer wg.Done()
			latest, err := fetchLatestForBump(cat.Sources[srcIdx])
			results[ri] = result{idx: srcIdx, latest: latest, err: err}
		}(i, idx)
	}
	wg.Wait()

	updates := 0
	for _, r := range results {
		s := &cat.Sources[r.idx]
		if r.err != nil {
			log.Printf("Failed to get latest version for %s: %v", s.Name, r.err)
			continue
		}
		isCommit := s.Bump != nil && (s.Bump.Method == "commit" || strings.Contains(s.Bump.TagFilter, "@commit"))
		current := s.Version
		if isCommit {
			current = s.Commit
		}
		if r.latest == "" || current == "" || r.latest == current {
			continue
		}
		if !isCommit && !isNewerVersion(current, r.latest) {
			continue
		}
		updates++
		log.Printf("New version for %s: %s -> %s", s.Name, current, r.latest)
		if isCommit {
			s.Commit = r.latest
		} else {
			s.Version = r.latest
			if s.ID == "ffmpeg" {
				cat.Release.FFmpegVersion = r.latest
			}
		}
	}

	if updates == 0 {
		log.Println("All libraries are up to date.")
		return nil
	}
	if u.DryRun {
		log.Println("Dry run enabled. No changes will be written.")
		return nil
	}
	if err := syncDockerfileFFmpegVersion(cat.Release.FFmpegVersion); err != nil {
		return err
	}
	if err := saveCatalog(path, cat); err != nil {
		return err
	}
	log.Println("Successfully updated", path)
	return nil
}

func fetchLatestForBump(s Source) (string, error) {
	b := s.Bump
	repo := b.Repo
	filter := b.TagFilter
	isCommit := b.Method == "commit" || strings.Contains(filter, "@commit")

	if isCommit {
		branch := b.Branch
		if branch == "" {
			re := regexp.MustCompile(`re:#\^refs/heads/(.+)\$#`)
			matches := re.FindStringSubmatch(filter)
			if len(matches) > 1 {
				branch = matches[1]
			}
		}
		if branch == "" {
			return "", fmt.Errorf("commit bump missing branch for %s", s.ID)
		}
		return getLatestGitCommit(repo, branch)
	}

	if strings.Contains(repo, "github.com") {
		return getLatestGitHubTag(repo)
	}
	if strings.Contains(repo, "gitlab.com") || strings.Contains(repo, "gitlab.gnome.org") || strings.Contains(repo, "gitlab.freedesktop.org") {
		return getLatestGitLabTag(repo)
	}
	return "", fmt.Errorf("unsupported bump repo for %s: %s", s.ID, repo)
}

func trimVersionTagPrefixes(tag string) string {
	cleanTag := strings.TrimPrefix(tag, "v")
	cleanTag = strings.TrimPrefix(cleanTag, "n")
	cleanTag = strings.TrimPrefix(cleanTag, "release-")
	cleanTag = strings.TrimPrefix(cleanTag, "lcms2.")
	cleanTag = strings.TrimPrefix(cleanTag, "lcms")
	return cleanTag
}

func isNumericVersion(tag string) bool {
	cleanTag := trimVersionTagPrefixes(tag)

	if strings.HasPrefix(tag, "PANGO_") {
		if regexp.MustCompile(`^PANGO_(\d+)_(\d+)_(\d+)$`).MatchString(tag) {
			return true
		}
		return regexp.MustCompile(`^PANGO_(\d+)_(\d+)$`).MatchString(tag)
	}
	if strings.Contains(cleanTag, "dev") || strings.Contains(cleanTag, "rc") ||
		strings.Contains(cleanTag, "alpha") || strings.Contains(cleanTag, "Alpha") {
		return false
	}
	if regexp.MustCompile(`^20\d{2}\.`).MatchString(cleanTag) {
		return false
	}
	return regexp.MustCompile(`^(\d+)\.(\d+)(\.(\d+))?$`).MatchString(cleanTag)
}

func stripPrefixes(tag string) string {
	if strings.HasPrefix(tag, "PANGO_") {
		if m := regexp.MustCompile(`^PANGO_(\d+)_(\d+)_(\d+)$`).FindStringSubmatch(tag); len(m) == 4 {
			return fmt.Sprintf("%s.%s.%s", m[1], m[2], m[3])
		}
		if m := regexp.MustCompile(`^PANGO_(\d+)_(\d+)$`).FindStringSubmatch(tag); len(m) == 3 {
			return fmt.Sprintf("%s.%s", m[1], m[2])
		}
	}
	cleanTag := trimVersionTagPrefixes(tag)
	return cleanTag
}

func parseSemanticVersion(tag string) (SemanticVersion, error) {
	cleanTag := tag
	if strings.HasPrefix(tag, "PANGO_") {
		if m := regexp.MustCompile(`^PANGO_(\d+)_(\d+)_(\d+)$`).FindStringSubmatch(tag); len(m) == 4 {
			cleanTag = fmt.Sprintf("%s.%s.%s", m[1], m[2], m[3])
		} else if m := regexp.MustCompile(`^PANGO_(\d+)_(\d+)$`).FindStringSubmatch(tag); len(m) == 3 {
			cleanTag = fmt.Sprintf("%s.%s", m[1], m[2])
		}
	} else {
		cleanTag = trimVersionTagPrefixes(cleanTag)
	}
	matches := regexp.MustCompile(`^(\d+)\.(\d+)(\.(\d+))?(-.*)?$`).FindStringSubmatch(cleanTag)
	if len(matches) < 3 {
		return SemanticVersion{}, fmt.Errorf("invalid semantic version: %s", tag)
	}
	major, _ := strconv.Atoi(matches[1])
	minor, _ := strconv.Atoi(matches[2])
	patch := 0
	if matches[4] != "" {
		patch, _ = strconv.Atoi(matches[4])
	}
	return SemanticVersion{Major: major, Minor: minor, Patch: patch, Tag: tag}, nil
}

func compareSemanticVersions(a, b SemanticVersion) int {
	if a.Major != b.Major {
		if a.Major > b.Major {
			return 1
		}
		return -1
	}
	if a.Minor != b.Minor {
		if a.Minor > b.Minor {
			return 1
		}
		return -1
	}
	if a.Patch != b.Patch {
		if a.Patch > b.Patch {
			return 1
		}
		return -1
	}
	return 0
}

func getLatestNumericVersion(tags []string) (string, error) {
	var numericVersions []SemanticVersion
	for _, tag := range tags {
		if isNumericVersion(tag) {
			if semVer, err := parseSemanticVersion(tag); err == nil {
				numericVersions = append(numericVersions, semVer)
			}
		}
	}
	if len(numericVersions) == 0 {
		return "", fmt.Errorf("no numeric version tags found")
	}
	sort.Slice(numericVersions, func(i, j int) bool {
		return compareSemanticVersions(numericVersions[i], numericVersions[j]) > 0
	})
	return stripPrefixes(numericVersions[0].Tag), nil
}

func getLatestNumericVersionForLCMS2(tags []string) (string, error) {
	var numericVersions []SemanticVersion
	for _, tag := range tags {
		if strings.HasPrefix(tag, "lcms2.") || isNumericVersion(tag) {
			if semVer, err := parseSemanticVersion(tag); err == nil {
				numericVersions = append(numericVersions, semVer)
			}
		}
	}
	if len(numericVersions) == 0 {
		return "", fmt.Errorf("no numeric version tags found")
	}
	sort.Slice(numericVersions, func(i, j int) bool {
		return compareSemanticVersions(numericVersions[i], numericVersions[j]) > 0
	})
	return stripPrefixes(numericVersions[0].Tag), nil
}

func isNewerVersion(currentVersion, newVersion string) bool {
	currentSemVer, err1 := parseSemanticVersion(currentVersion)
	newSemVer, err2 := parseSemanticVersion(newVersion)
	if err1 != nil || err2 != nil {
		return newVersion != currentVersion
	}
	return compareSemanticVersions(newSemVer, currentSemVer) > 0
}

func getLatestGitHubTag(repoURL string) (string, error) {
	re := regexp.MustCompile(`github\.com/([^/]+)/(.+)`)
	matches := re.FindStringSubmatch(repoURL)
	if len(matches) < 3 {
		return "", fmt.Errorf("invalid github URL: %s", repoURL)
	}
	owner, repo := matches[1], strings.TrimSuffix(matches[2], ".git")

	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		token = os.Getenv("PAT")
	}
	if token == "" {
		return "", fmt.Errorf("GITHUB_TOKEN not set")
	}

	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/tags?per_page=100", owner, repo)
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "token "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var tags []struct {
		Name string `json:"name"`
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if err := jsonUnmarshal(body, &tags); err != nil || len(tags) == 0 {
		return "", fmt.Errorf("failed to decode tags or no tags found for %s. Body: %s", repoURL, string(body))
	}
	tagNames := make([]string, len(tags))
	for i, t := range tags {
		tagNames[i] = t.Name
	}
	if repo == "Little-CMS" {
		return getLatestNumericVersionForLCMS2(tagNames)
	}
	return getLatestNumericVersion(tagNames)
}

func getLatestGitLabTag(repoURL string) (string, error) {
	re := regexp.MustCompile(`gitlab(?:\.gnome|\.freedesktop)?\.org/(.+)`)
	matches := re.FindStringSubmatch(repoURL)
	if len(matches) < 2 {
		return "", fmt.Errorf("invalid gitlab URL: %s", repoURL)
	}
	baseAPI := "https://gitlab.com"
	if strings.Contains(repoURL, "gitlab.gnome.org") {
		baseAPI = "https://gitlab.gnome.org"
	} else if strings.Contains(repoURL, "gitlab.freedesktop.org") {
		baseAPI = "https://gitlab.freedesktop.org"
	}
	project := url.PathEscape(strings.TrimSuffix(matches[1], ".git"))
	apiURL := fmt.Sprintf("%s/api/v4/projects/%s/repository/tags", baseAPI, project)
	resp, err := http.Get(apiURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var tags []struct {
		Name string `json:"name"`
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if err := jsonUnmarshal(body, &tags); err != nil || len(tags) == 0 {
		return "", fmt.Errorf("failed to decode tags or no tags found for %s. Body: %s", repoURL, string(body))
	}
	tagNames := make([]string, len(tags))
	for i, t := range tags {
		tagNames[i] = t.Name
	}
	return getLatestNumericVersion(tagNames)
}

func getLatestGitCommit(repoURL, branch string) (string, error) {
	repoURL = strings.TrimPrefix(repoURL, "gitrefs:")
	cmd := exec.Command("git", "ls-remote", repoURL, "refs/heads/"+branch)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(out))
	if len(fields) > 0 {
		return fields[0], nil
	}
	return "", fmt.Errorf("no commit found for %s on branch %s", repoURL, branch)
}

func runGit(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	if dir != "" && dir != "." {
		cmd.Dir = dir
	}
	out, err := cmd.Output()
	return string(out), err
}
