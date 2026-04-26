# BOOKFLOW · task-auth-pod · Auth Pod 작업용 (NAT + Azure VPN + Secrets endpoints)
#   대상: 영헌 (Auth Pod 개발 시 · Azure Entra OIDC 통신 필요)
#   전제: base-up.ps1 + task-msa-pods.ps1 (EKS 위에 Pod 배포)
#   소요: ~10분 (NAT + VPN)
#   비용: ~$1.50/일 (NAT $32/월 → 일 $1.07 + VPN)
#
#   ⚠️ Tier 50 nat-gateway · Tier 60 vpn-site-to-site 는 별도 작성 필요

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-auth-pod · NAT + Azure VPN + Secrets endpoints ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "vpc-egress" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "eks-cluster" -Tier "30")) {
    Write-Warn "EKS Cluster 미배포 · Pod 배포 전 task-msa-pods.ps1 필요"
}

# Secrets endpoints (이미 task-msa-pods 가 endpoints-bookflow-ai 올렸으면 skip)
if (-not (Test-Stack -Name "endpoints-bookflow-ai" -Tier "10")) {
    Deploy-Stack -Tier "10" -Name "endpoints-bookflow-ai" -Template "10-network-core/endpoints/endpoints-bookflow-ai.yaml"
}

# Tier 50 NAT (Egress VPC public · Auth Pod outbound to Azure · TGW 활성 시 cross-VPC 전용)
Deploy-Stack -Tier "50" -Name "nat-gateway" -Template "50-network-traffic/nat-gateway.yaml"

# Tier 60 Azure VPN (Customer Gateway IP 필요 · Phase 2 부터 활성)
# Deploy-Stack -Tier "60" -Name "vpn-site-to-site" -Template "60-network-cross-cloud/vpn-site-to-site.yaml" -Parameters @{ Provider = "azure" }
Write-Warn "Tier 60 vpn-site-to-site 는 아직 작성 전 · Azure VPN GW IP 확보 후 활성"

Write-Step "═══ task-auth-pod 완료 (Tier 50/60 placeholder) ═══"
