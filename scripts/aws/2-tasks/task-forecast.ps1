# BOOKFLOW · task-forecast · GCP VPN (forecast-svc Pod 가 Vertex AI Endpoint 통신)
#   대상: 우혁 (Vertex AI 통신 검증)
#   전제: base-up.ps1 + task-msa-pods.ps1 (forecast-svc EKS Pod 배포 후)
#   소요: ~5분 (VPN tunnel 설정)
#   비용: ~$1.50/일 (Site-to-Site VPN $36/월)
#
#   ⚠️ Tier 60 vpn-site-to-site 는 별도 작성 필요

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-forecast · GCP HA VPN ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "customer-gateway" -Tier "10")) {
    Write-Err "Customer Gateway 미배포 · base-up.ps1 먼저 실행"; exit 1
}

# Tier 60 GCP VPN (GCP HA VPN IP 확보 후 활성)
# Deploy-Stack -Tier "60" -Name "vpn-site-to-site" -Template "60-network-cross-cloud/vpn-site-to-site.yaml" -Parameters @{ Provider = "gcp" }
Write-Warn "Tier 60 vpn-site-to-site 는 아직 작성 전 · GCP HA VPN IP 확보 후 활성"

Write-Step "═══ task-forecast 완료 (Tier 60 placeholder) ═══"
