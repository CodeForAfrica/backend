package main

import (
	"encoding/json"
	"fmt"
	"testing"
)

func validValues() map[string]string {
	components := []component{}
	for _, name := range []string{"webapp-api", "webapp-httpd", "solr-zookeeper", "solr-shard-01", "rabbitmq-server", "extract-article-from-page", "maintenance", "pipeline", "topics", "annotators"} {
		components = append(components, component{name, "ecr-" + name})
	}
	data, _ := json.Marshal(components)
	return map[string]string{"aws-region": "eu-west-1", "ecs-cluster-name": "cluster", "ecs-service-name": "service", "task-family": "family", "app-url": "https://backend.civicsignal.dev.codeforafrica.org", "matrix": string(data)}
}
func TestPlanRejectsUnsafeDeploymentInputs(t *testing.T) {
	for _, test := range []struct{ name, key, value, account string }{
		{"wrong account", "", "", "123456789012"},
		{"wrong region", "aws-region", "eu-west-2", "499665620971"},
		{"production endpoint", "app-url", "https://civicsignal.org", "499665620971"},
		{"frontend endpoint", "app-url", "https://explorer.civicsignal.dev.codeforafrica.org", "499665620971"},
		{"missing service", "ecs-service-name", "", "499665620971"},
		{"partial release", "matrix", "[]", "499665620971"},
	} {
		t.Run(test.name, func(t *testing.T) {
			values := validValues()
			if test.key != "" {
				values[test.key] = test.value
			}
			if _, err := decodePlan(values, test.account); err == nil {
				t.Fatal("unsafe plan accepted")
			}
		})
	}
	values := validValues()
	p, err := decodePlan(values, "499665620971")
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Components) != 10 {
		t.Fatal("incomplete plan")
	}
}
func TestReadinessRequiresExpectedCompleteDeployment(t *testing.T) {
	var state serviceState
	err := json.Unmarshal([]byte(`{"taskDefinition":"new","desiredCount":1,"runningCount":1,"pendingCount":0,"deployments":[{"taskDefinition":"new","status":"PRIMARY","rolloutState":"COMPLETED"}]}`), &state)
	if err != nil {
		t.Fatal(err)
	}
	if !ready(state, "new") {
		t.Fatal("completed deployment rejected")
	}
	if ready(state, "old") {
		t.Fatal("wrong revision accepted")
	}
	state.Desired = 0
	state.Running = 0
	if ready(state, "new") {
		t.Fatal("zero running tasks accepted")
	}
	state.Desired = 1
	state.Running = 1
	state.Deployments[0].Rollout = "IN_PROGRESS"
	if ready(state, "new") {
		t.Fatal("incomplete deployment accepted")
	}
}
func TestPlanRejectsDuplicateComponents(t *testing.T) {
	values := validValues()
	var components []component
	json.Unmarshal([]byte(values["matrix"]), &components)
	components[1] = components[0]
	data, _ := json.Marshal(components)
	values["matrix"] = string(data)
	if _, err := decodePlan(values, "499665620971"); err == nil {
		t.Fatal(fmt.Sprintf("duplicate accepted: %s", data))
	}
}
