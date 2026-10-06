package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestResolveRequiresEveryContainerAndUsesTemplateExportNames(t *testing.T) {
	outputs := map[string]string{"civicsignalWebUrl": "https://app.example.org", "civicsignalAwsRegion": "eu-west-1", "civicsignalDeployGithubRoleArn": "role", "civicsignalWebClusterName": "cluster", "civicsignalWebServiceName": "service", "civicsignalWebTaskFamily": "family", "civicsignalWebWebappApiContainerName": "webapp-api", "civicsignalWebWebappApiRepositoryName": "api-repo", "civicsignalWebSolrShard01ContainerName": "solr-shard-01", "civicsignalWebSolrShard01RepositoryName": "solr-repo"}
	services := []service{{"webapp-api"}, {"solr-shard-01"}}
	result, err := resolve(outputs, services)
	if err != nil {
		t.Fatal(err)
	}
	var matrix []matrixService
	if err = json.Unmarshal([]byte(result["matrix"]), &matrix); err != nil {
		t.Fatal(err)
	}
	if len(matrix) != 2 || matrix[1].Repository != "solr-repo" {
		t.Fatal("wrong deployment matrix")
	}
	delete(outputs, "civicsignalWebSolrShard01RepositoryName")
	if _, err = resolve(outputs, services); err == nil || !strings.Contains(err.Error(), "solr-shard-01") {
		t.Fatal("missing infra container must block deployment")
	}
}
