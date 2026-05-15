param(
    [string] $ProjectId = "project-8ab6bf05-54d2-4f5d-b8d",
    [string] $Region = "asia-northeast1",
    [string] $EndpointId = "bookflow-forecast-endpoint"
)

$ErrorActionPreference = "Stop"

$endpoint = gcloud ai endpoints describe $EndpointId `
  --project=$ProjectId `
  --region=$Region `
  --format=json | ConvertFrom-Json

if (-not $endpoint.deployedModels) {
    Write-Host "No deployed models found on endpoint $EndpointId."
    exit 0
}

foreach ($model in $endpoint.deployedModels) {
    Write-Host "Undeploying deployed model id $($model.id) from endpoint $EndpointId"
    gcloud ai endpoints undeploy-model $EndpointId `
      --project=$ProjectId `
      --region=$Region `
      --deployed-model-id=$model.id
}

gcloud ai endpoints describe $EndpointId `
  --project=$ProjectId `
  --region=$Region `
  --format="json(name,displayName,deployedModels)"
