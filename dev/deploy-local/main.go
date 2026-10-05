// deploy-local publishes the complete CivicSignal runtime using the shared ECS release tool.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const appPath = "aws/account-499665620971-main/apps/civicsignal"

type component struct {
	Name       string `json:"name"`
	Repository string `json:"repository"`
}
type plan struct {
	Region, Cluster, Service, Family, URL, Registry string
	Components                                      []component
}
type releaseImage struct {
	ContainerName  string `json:"containerName"`
	ImageReference string `json:"imageReference"`
}
type serviceState struct {
	TaskDefinition string `json:"taskDefinition"`
	Desired        int    `json:"desiredCount"`
	Running        int    `json:"runningCount"`
	Pending        int    `json:"pendingCount"`
	Deployments    []struct {
		TaskDefinition string `json:"taskDefinition"`
		Status         string `json:"status"`
		Rollout        string `json:"rolloutState"`
		Failed         int    `json:"failedTasks"`
	} `json:"deployments"`
}

func logf(format string, args ...any) { fmt.Printf("[deploy-local] "+format+"\n", args...) }
func command(ctx context.Context, env []string, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Env = append(os.Environ(), env...)
	return cmd
}
func capture(ctx context.Context, env []string, name string, args ...string) ([]byte, error) {
	cmd := command(ctx, env, name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s failed (%v); inspect command credentials/permissions", name, err)
	}
	return out, nil
}
func stream(ctx context.Context, env []string, name string, args ...string) error {
	cmd := command(ctx, env, name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}
func decodePlan(values map[string]string, account string) (plan, error) {
	p := plan{Region: values["aws-region"], Cluster: values["ecs-cluster-name"], Service: values["ecs-service-name"], Family: values["task-family"], URL: values["app-url"]}
	if !regexp.MustCompile(`^[0-9]{12}$`).MatchString(account) {
		return p, errors.New("invalid AWS account")
	}
	if account != "499665620971" || p.Region != "eu-west-1" {
		return p, errors.New("CivicSignal dev deployment requires account 499665620971 in eu-west-1")
	}
	u, err := url.Parse(p.URL)
	if err != nil || u.Scheme != "https" || u.Host != "civicsignal.dev.codeforafrica.org" {
		return p, errors.New("expected CivicSignal dev HTTPS endpoint")
	}
	if p.Cluster == "" || p.Service == "" || p.Family == "" {
		return p, errors.New("missing ECS deployment outputs")
	}
	if err = json.Unmarshal([]byte(values["matrix"]), &p.Components); err != nil {
		return p, err
	}
	if len(p.Components) != 10 {
		return p, errors.New("expected all ten CivicSignal components")
	}
	seen := map[string]bool{}
	for _, c := range p.Components {
		if seen[c.Name] || !regexp.MustCompile(`^[a-z0-9-]+$`).MatchString(c.Name) || !regexp.MustCompile(`^[a-z0-9/_-]+$`).MatchString(c.Repository) {
			return p, errors.New("invalid or duplicate deployment component")
		}
		seen[c.Name] = true
	}
	p.Registry = account + ".dkr.ecr." + p.Region + ".amazonaws.com"
	return p, nil
}
func getState(ctx context.Context, env []string, p plan) (serviceState, error) {
	var s serviceState
	data, err := capture(ctx, env, "aws", "ecs", "describe-services", "--cluster", p.Cluster, "--services", p.Service, "--query", "services[0]", "--output", "json")
	if err != nil {
		return s, err
	}
	err = json.Unmarshal(data, &s)
	if err == nil && s.TaskDefinition == "" {
		err = errors.New("ECS service is absent")
	}
	return s, err
}
func ready(s serviceState, arn string) bool {
	return s.TaskDefinition == arn && s.Desired > 0 && s.Running == s.Desired && s.Pending == 0 && len(s.Deployments) == 1 && s.Deployments[0].Rollout == "COMPLETED"
}

func stoppedRelease(ctx context.Context, env []string, p plan, arn string) error {
	data, err := capture(ctx, env, "aws", "ecs", "list-tasks", "--cluster", p.Cluster, "--service-name", p.Service, "--desired-status", "STOPPED", "--max-items", "10", "--query", "taskArns", "--output", "json")
	if err != nil {
		return err
	}
	var tasks []string
	if err = json.Unmarshal(data, &tasks); err != nil || len(tasks) == 0 {
		return err
	}
	args := append([]string{"ecs", "describe-tasks", "--cluster", p.Cluster, "--tasks"}, tasks...)
	data, err = capture(ctx, env, "aws", args...)
	if err != nil {
		return err
	}
	var result struct {
		Tasks []struct {
			Definition string `json:"taskDefinitionArn"`
			Code       string `json:"stopCode"`
		} `json:"tasks"`
	}
	if err = json.Unmarshal(data, &result); err != nil {
		return err
	}
	for _, task := range result.Tasks {
		if task.Definition == arn && (task.Code == "TaskFailedToStart" || task.Code == "EssentialContainerExited") {
			return fmt.Errorf("new ECS task stopped (%s); inspect its stopped-task details", task.Code)
		}
	}
	return nil
}

func wait(ctx context.Context, env []string, p plan, arn string) error {
	deadline := time.Now().Add(30 * time.Minute)
	for attempt := 1; time.Now().Before(deadline); attempt++ {
		s, err := getState(ctx, env, p)
		if err != nil {
			return err
		}
		logf("Waiting for ECS (attempt %d): desired=%d running=%d pending=%d", attempt, s.Desired, s.Running, s.Pending)
		if ready(s, arn) {
			logf("OK - ECS service is stable on the released task definition")
			return nil
		}
		if s.TaskDefinition != arn {
			return errors.New("ECS changed to another task definition; deployment was rolled back or superseded")
		}
		if s.Desired == 0 {
			return errors.New("ECS service is paused; use --resume to deploy and resume dev")
		}
		for _, d := range s.Deployments {
			if d.Status == "PRIMARY" && (d.Rollout == "FAILED" || d.Failed >= 3) {
				return errors.New("ECS deployment failed; inspect ECS stopped task reasons")
			}
		}
		if err = stoppedRelease(ctx, env, p, arn); err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(15 * time.Second):
		}
	}
	return errors.New("ECS did not stabilize within 30 minutes")
}
func health(ctx context.Context, p plan) error {
	client := &http.Client{Timeout: 15 * time.Second}
	for attempt := 1; attempt <= 24; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(p.URL, "/")+"/status", nil)
		if err != nil {
			return err
		}
		response, err := client.Do(req)
		status := 0
		if err == nil {
			status = response.StatusCode
			io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
			response.Body.Close()
		}
		if status == 200 {
			logf("OK - HTTPS /status returned 200: %s", p.URL)
			return nil
		}
		logf("Waiting for HTTPS health (attempt %d/24, status=%d)", attempt, status)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(10 * time.Second):
		}
	}
	return errors.New("public HTTPS /status did not become healthy")
}
func deploy(ctx context.Context, env []string, p plan, infra, tmp string, resume bool) error {
	helper := filepath.Join(tmp, "ecs-release-images")
	logf("Compiling the same shared image-release helper used by GitHub Actions")
	if err := stream(ctx, env, "go", "build", "-o", helper, filepath.Join(infra, "tools/ecs-release-images/main.go")); err != nil {
		return err
	}
	logf("Initializing the selected runtime submodules")
	if err := stream(ctx, env, "git", "submodule", "update", "--init", "--recursive", "--", "apps/common/src/python/mediawords/languages/hi/hindi-hunspell", "apps/common/src/perl/MediaWords/Util/Mail/Message/Templates/email-templates", "apps/common/src/python/mediawords/languages/ca/snowball_stemmer", "apps/common/src/python/mediawords/languages/lt/snowball_stemmer", "apps/common/src/python/snowball"); err != nil {
		return err
	}
	sha, err := capture(ctx, env, "git", "rev-parse", "--short", "HEAD")
	if err != nil {
		return err
	}
	tag := "local-" + strings.TrimSpace(string(sha)) + "-" + time.Now().UTC().Format("20060102150405")
	logf("Authenticating Docker to ECR %s", p.Registry)
	password, err := capture(ctx, env, "aws", "ecr", "get-login-password")
	if err != nil {
		return err
	}
	login := command(ctx, env, "docker", "login", "--username", "AWS", "--password-stdin", p.Registry)
	login.Stdin = bytes.NewReader(password)
	login.Stdout = os.Stdout
	login.Stderr = os.Stderr
	if err = login.Run(); err != nil {
		return err
	}
	imagesDir := filepath.Join(tmp, "images")
	if err = os.Mkdir(imagesDir, 0700); err != nil {
		return err
	}
	for i, c := range p.Components {
		ref := p.Registry + "/" + c.Repository + ":" + tag
		logf("Building/pushing component %d/%d: %s (linux/amd64)", i+1, len(p.Components), c.Name)
		if err = stream(ctx, env, "docker", "buildx", "build", "--platform", "linux/amd64", "--build-arg", "CIVICSIGNAL_COMPONENT="+c.Name, "--tag", ref, "--push", "."); err != nil {
			return fmt.Errorf("build %s: %w", c.Name, err)
		}
		digest, err := capture(ctx, env, "aws", "ecr", "describe-images", "--repository-name", c.Repository, "--image-ids", "imageTag="+tag, "--query", "imageDetails[0].imageDigest", "--output", "text")
		if err != nil {
			return err
		}
		digestText := strings.TrimSpace(string(digest))
		if !regexp.MustCompile(`^sha256:[a-f0-9]{64}$`).MatchString(digestText) {
			return fmt.Errorf("missing immutable digest for %s", c.Name)
		}
		if err = writeJSON(filepath.Join(imagesDir, c.Name+".json"), releaseImage{c.Name, p.Registry + "/" + c.Repository + "@" + digestText}); err != nil {
			return err
		}
		logf("OK - published immutable image for %s", c.Name)
	}
	previous, err := getState(ctx, env, p)
	if err != nil {
		return err
	}
	rollback := ""
	if ready(previous, previous.TaskDefinition) {
		rollback = previous.TaskDefinition
	}
	logf("Reading latest template task shape; preserving its secrets, mounts and resource limits")
	definition, err := capture(ctx, env, "aws", "ecs", "describe-task-definition", "--task-definition", p.Family, "--query", "taskDefinition", "--output", "json")
	if err != nil {
		return err
	}
	current := filepath.Join(tmp, "current.json")
	next := filepath.Join(tmp, "next.json")
	if err = os.WriteFile(current, definition, 0600); err != nil {
		return err
	}
	releaseEnv := append(append([]string{}, env...), "ECR_REGISTRY="+p.Registry, "RELEASE_IMAGES_DIR="+imagesDir)
	if err = stream(ctx, releaseEnv, helper, "patch", current, next); err != nil {
		return err
	}
	logf("Registering one complete ten-container release")
	registered, err := capture(ctx, env, "aws", "ecs", "register-task-definition", "--cli-input-json", "file://"+next, "--query", "taskDefinition.taskDefinitionArn", "--output", "text")
	if err != nil {
		return err
	}
	arn := strings.TrimSpace(string(registered))
	if !strings.HasPrefix(arn, "arn:aws:ecs:") {
		return errors.New("invalid registered task definition")
	}
	logf("Updating ECS service %s to %s (stateful stop-before-start)", p.Service, arn)
	updateArgs := []string{"ecs", "update-service", "--cluster", p.Cluster, "--service", p.Service, "--task-definition", arn, "--output", "json"}
	if resume {
		updateArgs = append(updateArgs, "--desired-count", "1")
	}
	if _, err = capture(ctx, env, "aws", updateArgs...); err != nil {
		return err
	}
	if err = wait(ctx, env, p, arn); err == nil {
		err = health(ctx, p)
	}
	if err != nil {
		if rollback == "" {
			logf("No verified previous deployment exists; leaving the failed first deployment visible")
			return err
		}
		// Do not overwrite a release another operator started during this run.
		state, stateErr := getState(ctx, env, p)
		if stateErr != nil {
			return fmt.Errorf("%w; unable to inspect rollback safety", err)
		}
		if state.TaskDefinition != arn {
			return err
		}
		logf("Deployment failed; restoring verified task definition %s", rollback)
		if _, restoreErr := capture(ctx, env, "aws", "ecs", "update-service", "--cluster", p.Cluster, "--service", p.Service, "--task-definition", rollback, "--output", "json"); restoreErr != nil {
			return fmt.Errorf("%w; rollback update failed", err)
		}
		if restoreErr := wait(ctx, env, p, rollback); restoreErr != nil {
			return fmt.Errorf("%w; rollback did not stabilize", err)
		}
		logf("OK - previous deployment restored")
		return err
	}
	return nil
}
func run(ctx context.Context) error {
	infraDefault := os.Getenv("INFRA_REPO")
	if infraDefault == "" {
		infraDefault = "../iac-cfa-pulumi"
	}
	infra := flag.String("infra-repo", infraDefault, "local IaC checkout containing CivicSignal and shared release tooling")
	stack := flag.String("stack", "dev", "Pulumi dev stack")
	profile := flag.String("profile", "cfa-bootstrap", "AWS CLI profile")
	check := flag.Bool("check", false, "validate live deployment inputs without building or deploying")
	resume := flag.Bool("resume", false, "resume a paused dev service with one task on successful image publication")
	flag.Parse()
	if flag.NArg() != 0 {
		return errors.New("unexpected arguments")
	}
	if *stack != "dev" {
		return errors.New("this tool deploys dev only")
	}
	if *infra == "" {
		return errors.New("pass --infra-repo /path/to/iac-cfa-pulumi (or INFRA_REPO)")
	}
	absolute, err := filepath.Abs(*infra)
	if err != nil {
		return err
	}
	if _, err = os.Stat(filepath.Join(absolute, appPath, "Pulumi.yaml")); err != nil {
		return fmt.Errorf("CivicSignal infrastructure project not found in %s; pass --infra-repo with the correct checkout", absolute)
	}
	for _, name := range []string{"aws", "docker", "go", "git", "pulumi"} {
		if _, err = exec.LookPath(name); err != nil {
			return fmt.Errorf("%s is required", name)
		}
	}
	tmp, err := os.MkdirTemp("", "civicsignal-deploy-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	env := []string{"AWS_PROFILE=" + *profile, "AWS_REGION=eu-west-1", "AWS_DEFAULT_REGION=eu-west-1", "AWS_PAGER="}
	logf("Reading dev Pulumi outputs from %s", absolute)
	outputs, err := capture(ctx, env, "pulumi", "stack", "output", "--cwd", filepath.Join(absolute, appPath), "--stack", *stack, "--json")
	if err != nil {
		return err
	}
	outputsFile := filepath.Join(tmp, "outputs.json")
	if err = os.WriteFile(outputsFile, outputs, 0600); err != nil {
		return err
	}
	contractFile := filepath.Join(tmp, "contract.txt")
	if err = os.WriteFile(contractFile, nil, 0600); err != nil {
		return err
	}
	contractEnv := append(append([]string{}, env...), "GITHUB_OUTPUT="+contractFile)
	if err = stream(ctx, contractEnv, "go", "run", "dev/runtime-contract/main.go", outputsFile); err != nil {
		return err
	}
	contract, err := os.ReadFile(contractFile)
	if err != nil {
		return err
	}
	values := map[string]string{}
	for _, line := range strings.Split(string(contract), "\n") {
		if key, value, ok := strings.Cut(line, "="); ok {
			values[key] = value
		}
	}
	account, err := capture(ctx, env, "aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")
	if err != nil {
		return err
	}
	p, err := decodePlan(values, strings.TrimSpace(string(account)))
	if err != nil {
		return err
	}
	if _, err = getState(ctx, env, p); err != nil {
		return err
	}
	logf("OK - dev deployment contract has all %d containers: %s", len(p.Components), p.URL)
	if *check {
		return nil
	}
	logf("Manual local build publishes ten images to ECR; no GitHub build jobs are triggered")
	return deploy(ctx, env, p, absolute, tmp, *resume)
}
func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	if err := run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, "[deploy-local] ERROR:", err)
		os.Exit(1)
	}
}
