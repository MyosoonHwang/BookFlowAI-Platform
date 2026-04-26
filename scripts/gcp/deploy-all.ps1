$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "config\gcp.ps1")
. (Join-Path $ScriptDir "_lib\tf-helper.ps1")

$env:GOOGLE_CLOUD_PROJECT = $GcpConfig.ProjectID
$env:GOOGLE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_CORE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_COMPUTE_REGION = $GcpConfig.Region

Invoke-TerraformLayer -Config $GcpConfig -Layer "00-foundation"

Read-Host "Check AWS peer IPs and VPN shared secret values for 20-network-daily, then press Enter to continue"

Invoke-TerraformLayer -Config $GcpConfig -Layer "20-network-daily"
Invoke-TerraformLayer -Config $GcpConfig -Layer "99-content"
