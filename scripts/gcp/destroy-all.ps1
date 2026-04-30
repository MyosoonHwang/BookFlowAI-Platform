$ErrorActionPreference = "Stop"
$GcpScriptRoot = $PSScriptRoot

. (Join-Path $GcpScriptRoot "config\gcp.ps1")
. (Join-Path $GcpScriptRoot "_lib\tf-helper.ps1")

$env:GOOGLE_CLOUD_PROJECT = $GcpConfig.ProjectID
$env:GOOGLE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_CORE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_COMPUTE_REGION = $GcpConfig.Region

# 1. 서비스 레이어 삭제
Invoke-TerraformLayer -Config $GcpConfig -Layer "99-content" -Action "destroy"

# 2. 네트워크 레이어 삭제 (배포를 안 했으므로 주석 처리)
# Invoke-TerraformLayer -Config $GcpConfig -Layer "20-network-daily" -Action "destroy"

# 3. 기초 레이어 삭제
Invoke-TerraformLayer -Config $GcpConfig -Layer "00-foundation" -Action "destroy"