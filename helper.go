package main

import (
	"bufio"
	"encoding/json"
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

	"github.com/alecthomas/kong"
)

var cli struct {
	Update UpdateCmd `cmd:"" help:"Check for new dependency versions and update fetch-sources.sh."`
}

type UpdateCmd struct {
	DryRun bool `help:"Show what would be updated without applying any changes."`
}

func (u *UpdateCmd) Run() error {
	log.Println("Starting version check for", fetchScriptPath)

	fileContent, err := os.ReadFile(fetchScriptPath)
	if err != nil {
		log.Fatalf("Failed to read %s: %v", fetchScriptPath, err)
	}

	libraries := parseLibraries(string(fileContent))

	var wg sync.WaitGroup
	for i := range libraries {
		wg.Add(1)
		go func(lib *Library) {
			defer wg.Done()
			getLatestVersion(lib)
		}(&libraries[i])
	}
	wg.Wait()

	// Update the script file with new versions
	updatesFound := false
	newContent := string(fileContent)
	for _, lib := range libraries {
		if lib.LatestVersion != "" && lib.CurrentVersion != "" && lib.LatestVersion != lib.CurrentVersion {
			// Only update if it's actually a newer version
			if isNewerVersion(lib.CurrentVersion, lib.LatestVersion) {
				updatesFound = true
				log.Printf("New version for %s: %s -> %s", lib.Name, lib.CurrentVersion, lib.LatestVersion)

				oldLine := fmt.Sprintf(`: "${%s:=%s}"`, lib.VarName, lib.CurrentVersion)
				newLine := fmt.Sprintf(`: "${%s:=%s}"`, lib.VarName, lib.LatestVersion)
				newContent = strings.Replace(newContent, oldLine, newLine, 1)
			}
		}
	}

	if updatesFound {
		if u.DryRun {
			log.Println("Dry run enabled. No changes will be written.")
			return nil
		}
		// Create a backup
		if err := os.Rename(fetchScriptPath, fetchScriptPath+".bak"); err != nil {
			log.Fatalf("Failed to create backup: %v", err)
		}
		// Write the updated content
		if err := os.WriteFile(fetchScriptPath, []byte(newContent), 0755); err != nil {
			log.Fatalf("Failed to write updated script: %v", err)
		}
		log.Println("Successfully updated", fetchScriptPath)
	} else {
		log.Println("All libraries are up to date.")
	}

	log.Println("Version check finished.")
	return nil
}

const fetchScriptPath = "fetch-sources.sh"

type Library struct {
	Name           string
	VersionRegex   string
	URL            string
	Filter         string
	VarNameBase    string
	VarName        string
	CurrentVersion string
	LatestVersion  string
	IsCommitBased  bool
}

type SemanticVersion struct {
	Major int
	Minor int
	Patch int
	Tag   string
}

// isNumericVersion checks if a tag represents a numeric version (x.y or x.y.z format)
func isNumericVersion(tag string) bool {
	// Remove common prefixes (v, n, release-, lcms)
	cleanTag := strings.TrimPrefix(tag, "v")
	cleanTag = strings.TrimPrefix(cleanTag, "n")
	cleanTag = strings.TrimPrefix(cleanTag, "release-")
	cleanTag = strings.TrimPrefix(cleanTag, "lcms")
	cleanTag = strings.TrimPrefix(cleanTag, "lcms2.")

	// Handle PANGO_X_Y_Z format
	if strings.HasPrefix(tag, "PANGO_") {
		// Convert PANGO_1_23_0 to 1.23.0
		pangoRegex := regexp.MustCompile(`^PANGO_(\d+)_(\d+)_(\d+)$`)
		if pangoRegex.MatchString(tag) {
			return true
		}
		// Convert PANGO_1_23 to 1.23
		pangoRegex2 := regexp.MustCompile(`^PANGO_(\d+)_(\d+)$`)
		if pangoRegex2.MatchString(tag) {
			return true
		}
		return false
	}

	// Skip development tags and rc versions
	if strings.Contains(cleanTag, "dev") || strings.Contains(cleanTag, "rc") || strings.Contains(cleanTag, "alpha") || strings.Contains(cleanTag, "Alpha") {
		return false
	}

	// Match numeric version pattern: x.y or x.y.z (no suffixes allowed)
	numVerRegex := regexp.MustCompile(`^(\d+)\.(\d+)(\.(\d+))?$`)
	return numVerRegex.MatchString(cleanTag)
}

// stripPrefixes removes common version prefixes and returns clean numeric version
func stripPrefixes(tag string) string {
	// Handle PANGO_X_Y_Z format
	if strings.HasPrefix(tag, "PANGO_") {
		// Convert PANGO_1_23_0 to 1.23.0
		pangoRegex := regexp.MustCompile(`^PANGO_(\d+)_(\d+)_(\d+)$`)
		matches := pangoRegex.FindStringSubmatch(tag)
		if len(matches) == 4 {
			return fmt.Sprintf("%s.%s.%s", matches[1], matches[2], matches[3])
		}
		// Convert PANGO_1_23 to 1.23
		pangoRegex2 := regexp.MustCompile(`^PANGO_(\d+)_(\d+)$`)
		matches2 := pangoRegex2.FindStringSubmatch(tag)
		if len(matches2) == 3 {
			return fmt.Sprintf("%s.%s", matches2[1], matches2[2])
		}
	}

	cleanTag := strings.TrimPrefix(tag, "v")
	cleanTag = strings.TrimPrefix(cleanTag, "n")
	cleanTag = strings.TrimPrefix(cleanTag, "release-")
	cleanTag = strings.TrimPrefix(cleanTag, "lcms")
	cleanTag = strings.TrimPrefix(cleanTag, "lcms2.")
	return cleanTag
}

// parseSemanticVersion parses a semantic version tag into components
func parseSemanticVersion(tag string) (SemanticVersion, error) {
	cleanTag := tag

	// Handle PANGO_X_Y_Z format
	if strings.HasPrefix(tag, "PANGO_") {
		// Convert PANGO_1_23_0 to 1.23.0
		pangoRegex := regexp.MustCompile(`^PANGO_(\d+)_(\d+)_(\d+)$`)
		matches := pangoRegex.FindStringSubmatch(tag)
		if len(matches) == 4 {
			cleanTag = fmt.Sprintf("%s.%s.%s", matches[1], matches[2], matches[3])
		} else {
			// Convert PANGO_1_23 to 1.23
			pangoRegex2 := regexp.MustCompile(`^PANGO_(\d+)_(\d+)$`)
			matches2 := pangoRegex2.FindStringSubmatch(tag)
			if len(matches2) == 3 {
				cleanTag = fmt.Sprintf("%s.%s", matches2[1], matches2[2])
			}
		}
	} else {
		cleanTag = strings.TrimPrefix(cleanTag, "v")
		cleanTag = strings.TrimPrefix(cleanTag, "n")
		cleanTag = strings.TrimPrefix(cleanTag, "release-")
		cleanTag = strings.TrimPrefix(cleanTag, "lcms")
		cleanTag = strings.TrimPrefix(cleanTag, "lcms2.")
	}

	// Match semantic version pattern: x.y.z or x.y (optionally with suffixes like -beta, -rc1, etc)
	semVerRegex := regexp.MustCompile(`^(\d+)\.(\d+)(\.(\d+))?(-.*)?$`)
	matches := semVerRegex.FindStringSubmatch(cleanTag)
	if len(matches) < 3 {
		return SemanticVersion{}, fmt.Errorf("invalid semantic version: %s", tag)
	}

	major, _ := strconv.Atoi(matches[1])
	minor, _ := strconv.Atoi(matches[2])
	patch := 0
	if matches[4] != "" {
		patch, _ = strconv.Atoi(matches[4])
	}

	return SemanticVersion{
		Major: major,
		Minor: minor,
		Patch: patch,
		Tag:   tag,
	}, nil
}

// compareSemanticVersions compares two semantic versions. Returns:
// -1 if a < b, 0 if a == b, 1 if a > b
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

// getLatestNumericVersion filters and sorts tags to find the latest numeric version
func getLatestNumericVersion(tags []string) (string, error) {
	var numericVersions []SemanticVersion

	for _, tag := range tags {
		if isNumericVersion(tag) {
			semVer, err := parseSemanticVersion(tag)
			if err == nil {
				numericVersions = append(numericVersions, semVer)
			}
		}
	}

	if len(numericVersions) == 0 {
		return "", fmt.Errorf("no numeric version tags found")
	}

	// Sort by semantic version (latest first)
	sort.Slice(numericVersions, func(i, j int) bool {
		return compareSemanticVersions(numericVersions[i], numericVersions[j]) > 0
	})

	// Return the original tag without prefix modifications
	return stripPrefixes(numericVersions[0].Tag), nil
}

// getLatestNumericVersionForLCMS2 handles lcms2's special tag format
func getLatestNumericVersionForLCMS2(tags []string) (string, error) {
	var numericVersions []SemanticVersion

	for _, tag := range tags {
		// Look for tags like "lcms2.17" or clean versions like "2.17"
		if strings.HasPrefix(tag, "lcms2.") || isNumericVersion(tag) {
			semVer, err := parseSemanticVersion(tag)
			if err == nil {
				numericVersions = append(numericVersions, semVer)
			}
		}
	}

	if len(numericVersions) == 0 {
		return "", fmt.Errorf("no numeric version tags found")
	}

	// Sort by semantic version (latest first)
	sort.Slice(numericVersions, func(i, j int) bool {
		return compareSemanticVersions(numericVersions[i], numericVersions[j]) > 0
	})

	// Return in lcms2.X format (script expects this format)
	latest := numericVersions[0]
	cleanVersion := stripPrefixes(latest.Tag)
	return "lcms2." + cleanVersion, nil
}

// isNewerVersion checks if newVersion is newer than currentVersion
func isNewerVersion(currentVersion, newVersion string) bool {
	// Handle original tag formats (with prefixes)
	currentSemVer, err1 := parseSemanticVersion(currentVersion)
	newSemVer, err2 := parseSemanticVersion(newVersion)

	if err1 != nil || err2 != nil {
		// If we can't parse as versions, do string comparison
		return newVersion != currentVersion
	}

	return compareSemanticVersions(newSemVer, currentSemVer) > 0
}

func main() {
	ctx := kong.Parse(&cli)
	err := ctx.Run()
	ctx.FatalIfErrorf(err)
}

func getLatestVersion(lib *Library) {
	var err error

	if strings.Contains(lib.URL, "github.com") {
		lib.LatestVersion, err = getLatestGitHubTag(lib.URL)
	} else if strings.Contains(lib.URL, "gitlab.com") || strings.Contains(lib.URL, "gitlab.gnome.org") {
		lib.LatestVersion, err = getLatestGitLabTag(lib.URL)
	} else if strings.HasPrefix(lib.URL, "gitrefs:") {
		branchRegex := regexp.MustCompile(`re:#^refs/heads/(.*)\$#`)
		matches := branchRegex.FindStringSubmatch(lib.Filter)
		if len(matches) > 1 {
			branch := matches[1]
			lib.LatestVersion, err = getLatestGitCommit(lib.URL, branch)
		}
	} else {
		// log.Printf("Skipping unsupported URL for %s: %s", lib.Name, lib.URL)
	}

	if err != nil {
		log.Printf("Failed to get latest version for %s: %v", lib.Name, err)
	}
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
		log.Println("Warning: GITHUB_TOKEN not set. You may hit rate limits.")
	}
	client := &http.Client{}

	// Get all tags instead of just the latest release
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/tags?per_page=100", owner, repo)
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", err
	}
	if token != "" {
		req.Header.Set("Authorization", "token "+token)
	}

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var tags []struct {
		Name string `json:"name"`
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read tags response for %s: %v", repoURL, err)
	}
	if err := json.Unmarshal(body, &tags); err != nil || len(tags) == 0 {
		return "", fmt.Errorf("failed to decode tags or no tags found for %s. Body: %s", repoURL, string(body))
	}

	// Extract tag names and filter for numeric versions
	var tagNames []string
	for _, tag := range tags {
		tagNames = append(tagNames, tag.Name)
	}

	// Special handling for lcms2 which expects "lcms2.X" format
	if repo == "Little-CMS" {
		return getLatestNumericVersionForLCMS2(tagNames)
	}

	return getLatestNumericVersion(tagNames)
}

func getLatestGitLabTag(repoURL string) (string, error) {
	re := regexp.MustCompile(`gitlab(?:\.gnome)?\.org/(.+)`)
	matches := re.FindStringSubmatch(repoURL)
	if len(matches) < 2 {
		return "", fmt.Errorf("invalid gitlab URL: %s", repoURL)
	}

	baseAPI := "https://gitlab.com"
	if strings.Contains(repoURL, "gitlab.gnome.org") {
		baseAPI = "https://gitlab.gnome.org"
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
		return "", fmt.Errorf("failed to read tags response for %s: %v", repoURL, err)
	}
	if err := json.Unmarshal(body, &tags); err != nil || len(tags) == 0 {
		return "", fmt.Errorf("failed to decode tags or no tags found for %s. Body: %s", repoURL, string(body))
	}

	// Extract tag names and filter for numeric versions
	var tagNames []string
	for _, tag := range tags {
		tagNames = append(tagNames, tag.Name)
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

func parseLibraries(content string) []Library {
	var libs []Library
	bumpRegex := regexp.MustCompile(`^# bump: (\S+)\s+(\S+)\s+(\S+.*)`)

	scanner := bufio.NewScanner(strings.NewReader(content))
	for scanner.Scan() {
		line := scanner.Text()
		if matches := bumpRegex.FindStringSubmatch(line); len(matches) > 0 {
			// Skip "after" and "link" lines
			if matches[2] == "after" || matches[2] == "link" {
				continue
			}

			lib := Library{
				Name:         matches[1],
				VersionRegex: matches[2],
			}

			urlAndFilter := strings.Split(matches[3], "|")
			lib.URL = urlAndFilter[0]
			if len(urlAndFilter) > 1 {
				lib.Filter = strings.Join(urlAndFilter[1:], "|")
			}

			lib.IsCommitBased = strings.Contains(lib.Filter, "@commit")

			// Extract VarNameBase and set VarName
			varNameRegex := regexp.MustCompile(`/([A-Z0-9]+)_(VERSION|COMMIT)`)
			if varNameMatches := varNameRegex.FindStringSubmatch(lib.VersionRegex); len(varNameMatches) > 2 {
				lib.VarNameBase = varNameMatches[1]
				if lib.IsCommitBased {
					lib.VarName = lib.VarNameBase + "_COMMIT"
				} else {
					lib.VarName = lib.VarNameBase + "_VERSION"
				}
			}

			// Extract current version
			versionLineRegex := regexp.MustCompile(fmt.Sprintf(`: "\${%s:=(.*)}"`, lib.VarName))
			if versionMatches := versionLineRegex.FindStringSubmatch(content); len(versionMatches) > 1 {
				lib.CurrentVersion = versionMatches[1]
			}

			libs = append(libs, lib)
		}
	}
	return libs
}
