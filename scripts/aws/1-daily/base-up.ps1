# BOOKFLOW · 매일 아침 09:00 · Base 네트워크 + 기초 인프라 구축
#   Tier 00 영구 자원은 이미 있다고 가정 (phase0-foundation.ps1 1회 실행 완료)
#   올리는 것: Tier 10 (VPC 5개 + CGW + Route 53)
#   Endpoints · Peering은 각 task 스크립트가 필요 시 추가 deploy
#   RDS/Redis/Kinesis · EKS/ECS 등은 task 별로 (20·30·40 Tier)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")
. (Join-Path $PSScriptRoot "..\utils\show-cross-cloud-exports.ps1" -ErrorAction SilentlyContinue)

Write-Step "═══ 매일 아침 · Base 네트워크 구축 ═══"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패"
    exit 1
}

# ─────────────────────────────────────────────────
# Tier 10 · Network Core
# ─────────────────────────────────────────────────
# 1. VPC 5개 (독립 · 순서 무관하지만 명시적으로)
Deploy-Stack -Tier "10" -Name "vpc-bookflow-ai"  -Template "10-network-core/vpc-bookflow-ai.yaml"
Deploy-Stack -Tier "10" -Name "vpc-sales-data"   -Template "10-network-core/vpc-sales-data.yaml"
Deploy-Stack -Tier "10" -Name "vpc-egress"       -Template "10-network-core/vpc-egress.yaml"
Deploy-Stack -Tier "10" -Name "vpc-data"         -Template "10-network-core/vpc-data.yaml"
Deploy-Stack -Tier "10" -Name "vpc-ansible"      -Template "10-network-core/vpc-ansible.yaml"

# 2. Customer Gateway (IP 있을 때만 실 생성)
Deploy-Stack -Tier "10" -Name "customer-gateway" -Template "10-network-core/customer-gateway.yaml"

# 3. Route 53 Private Zone (5 VPC Import 완료 후)
Deploy-Stack -Tier "10" -Name "route53"          -Template "10-network-core/route53.yaml"

Write-Step "═══ Base 배포 완료 ═══"
Write-Info "Endpoints · Peering은 각 task 스크립트가 필요 시 배포."
Write-Info "예: .\scripts\aws\2-tasks\task-msa-pods.ps1"

# Azure/GCP 팀에 공유할 정보 출력
if (Get-Command Show-CrossCloudExports -ErrorAction SilentlyContinue) {
    Show-CrossCloudExports
}

Show-AllStacks
