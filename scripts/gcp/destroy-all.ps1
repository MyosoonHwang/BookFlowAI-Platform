$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "config\gcp.ps1")
. (Join-Path $ScriptDir "_lib\tf-helper.ps1")

$env:GOOGLE_CLOUD_PROJECT = $GcpConfig.ProjectID
$env:GOOGLE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_CORE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_COMPUTE_REGION = $GcpConfig.Region

Invoke-TerraformLayer -Config $GcpConfig -Layer "99-content" -Action "destroy"
Invoke-TerraformLayer -Config $GcpConfig -Layer "20-network-daily" -Action "destroy"
Invoke-TerraformLayer -Config $GcpConfig -Layer "00-foundation" -Action "destroy"
