$ErrorActionPreference = "Stop"

# $PSScriptRoot는 현재 스크립트가 위치한 디렉토리를 가리키는 내장 변수입니다.
# 변수 충돌을 방지하기 위해 Join-Path에 직접 사용하거나 별도의 이름을 가진 변수에 저장합니다.
$GcpScriptRoot = $PSScriptRoot

# 설정 및 라이브러리 로드
. (Join-Path $GcpScriptRoot "config\gcp.ps1")
. (Join-Path $GcpScriptRoot "_lib\tf-helper.ps1")

# 환경 변수 설정
$env:GOOGLE_CLOUD_PROJECT = $GcpConfig.ProjectID
$env:GOOGLE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_CORE_PROJECT = $GcpConfig.ProjectID
$env:CLOUDSDK_COMPUTE_REGION = $GcpConfig.Region

# 1. 기초 레이어 배포
Invoke-TerraformLayer -Config $GcpConfig -Layer "00-foundation"

# 2. 네트워크 레이어 배포 (AWS IP 대기 중이므로 주석 처리)
# Read-Host "Check AWS peer IPs and VPN shared secret values for 20-network-daily, then press Enter to continue"
Invoke-TerraformLayer -Config $GcpConfig -Layer "20-network-daily"

# 3. 서비스 레이어 배포
Invoke-TerraformLayer -Config $GcpConfig -Layer "99-content"