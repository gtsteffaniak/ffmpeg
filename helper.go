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
			updatesFound = true
			log.Printf("New version for %s: %s -> %s", lib.Name, lib.CurrentVersion, lib.LatestVersion)

			oldLine := fmt.Sprintf(`: "${%s:=%s}"`, lib.VarName, lib.CurrentVersion)
			newLine := fmt.Sprintf(`: "${%s:=%s}"`, lib.VarName, lib.LatestVersion)
			newContent = strings.Replace(newContent, oldLine, newLine, 1)
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

func main() {
	ctx := kong.Parse(&cli)
	err := ctx.Run()
	ctx.FatalIfErrorf(err)
}

func getLatestVersion(lib *Library) {
	var err error
	if strings.Contains(lib.URL, "github.com") {
		lib.LatestVersion, err = getLatestGitHubTag(lib.URL)
		lib.LatestVersion = strings.TrimPrefix(lib.LatestVersion, "v")
		lib.LatestVersion = strings.TrimPrefix(lib.LatestVersion, "release-")
	} else if strings.Contains(lib.URL, "gitlab.com") || strings.Contains(lib.URL, "gitlab.gnome.org") {
		lib.LatestVersion, err = getLatestGitLabTag(lib.URL)
		lib.LatestVersion = strings.TrimPrefix(lib.LatestVersion, "v")
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
	// ... implementation from shell script in Go ...
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

	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", err
	}
	if token != "" {
		req.Header.Set("Authorization", "token "+token)
	}

	resp, err := client.Do(req)
	if err != nil || resp.StatusCode != http.StatusOK {
		apiURL = fmt.Sprintf("https://api.github.com/repos/%s/%s/tags", owner, repo)
		req, err = http.NewRequest("GET", apiURL, nil)
		if err != nil {
			return "", err
		}
		if token != "" {
			req.Header.Set("Authorization", "token "+token)
		}
		resp, err = client.Do(req)
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
		return tags[0].Name, nil
	}
	defer resp.Body.Close()

	var release struct {
		TagName string `json:"tag_name"`
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read release response for %s: %v", repoURL, err)
	}
	if err := json.Unmarshal(body, &release); err != nil {
		return "", fmt.Errorf("failed to decode release for %s. Body: %s", repoURL, string(body))
	}
	return release.TagName, nil
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
	return tags[0].Name, nil
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
