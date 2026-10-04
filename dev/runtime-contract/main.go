package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type service struct {
	Name string `json:"name"`
}
type matrixService struct {
	Name       string `json:"name"`
	Repository string `json:"repository"`
}

func exportName(name string) string {
	var result strings.Builder
	for _, part := range strings.Split(name, "-") {
		if part != "" {
			result.WriteString(strings.ToUpper(part[:1]) + part[1:])
		}
	}
	return result.String()
}
func resolve(outputs map[string]string, services []service) (map[string]string, error) {
	required := map[string]string{"app-url": "civicsignalWebUrl", "aws-region": "civicsignalAwsRegion", "aws-role-to-assume": "civicsignalDeployGithubRoleArn", "ecs-cluster-name": "civicsignalWebClusterName", "ecs-service-name": "civicsignalWebServiceName", "task-family": "civicsignalWebTaskFamily"}
	resolved := map[string]string{}
	for name, key := range required {
		value := outputs[key]
		if value == "" || strings.ContainsAny(value, "\r\n") {
			return nil, fmt.Errorf("missing or invalid public infrastructure output %s", key)
		}
		resolved[name] = value
	}
	var matrix []matrixService
	for _, s := range services {
		prefix := "civicsignalWeb" + exportName(s.Name)
		if outputs[prefix+"ContainerName"] != s.Name || outputs[prefix+"RepositoryName"] == "" {
			return nil, fmt.Errorf("infrastructure does not define runtime container %s", s.Name)
		}
		matrix = append(matrix, matrixService{s.Name, outputs[prefix+"RepositoryName"]})
		if s.Name == "webapp-api" {
			resolved["primary-repository"] = outputs[prefix+"RepositoryName"]
		}
	}
	if resolved["primary-repository"] == "" {
		return nil, fmt.Errorf("webapp-api missing from runtime")
	}
	data, err := json.Marshal(matrix)
	if err != nil {
		return nil, err
	}
	resolved["matrix"] = string(data)
	return resolved, nil
}
func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: runtime-contract stack-outputs.json")
		os.Exit(1)
	}
	outputsData, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	var rawOutputs map[string]json.RawMessage
	if err = json.Unmarshal(outputsData, &rawOutputs); err != nil {
		panic(err)
	}
	outputs := map[string]string{}
	// Shared stack outputs may also include subnet arrays and structured data.
	for name, raw := range rawOutputs {
		var value string
		if json.Unmarshal(raw, &value) == nil {
			outputs[name] = value
		}
	}
	servicesData, err := os.ReadFile("runtime-services.json")
	if err != nil {
		panic(err)
	}
	var services []service
	if err = json.Unmarshal(servicesData, &services); err != nil {
		panic(err)
	}
	values, err := resolve(outputs, services)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	output, err := os.OpenFile(os.Getenv("GITHUB_OUTPUT"), os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		panic(err)
	}
	defer output.Close()
	for name, value := range values {
		if strings.ContainsAny(value, "\r\n") {
			panic("invalid workflow output")
		}
		fmt.Fprintf(output, "%s=%s\n", name, value)
	}
}
