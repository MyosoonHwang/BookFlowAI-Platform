# BOOKFLOW · 매일 아침 09:00 · Base 네트워크 + 기초 인프라 구축
#   Tier 00 영구 자원은 이미 있다고 가정 (phase0-foundation.ps1 1회 실행 완료)
#   올리는 것:
#     Tier 10 (VPC 5 + CGW + Route 53)
#     Tier 20 (RDS/Redis/Kinesis · 구축 설정)
#     Tier 30 (EKS Control Plane + ECS Cluster + ALB Controller IRSA + Ansible Node)
#   Endpoints · Peering은 각 task 스크립트가 필요 시 추가 deploy
#   Pod/Task/Node Group/Publisher ASG는 Tier 40 (task 별 또는 task-msa-pods.ps1)
#   RDS/Redis 고가용 (Multi-AZ · Replication) 은 task-scenario-ha.ps1 에서 toggle

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

# ─────────────────────────────────────────────────
# Tier 20 · Data Persistent (구축 모드 · Single-AZ · 저비용)
# ─────────────────────────────────────────────────
# RDS: Single-AZ (EnableMultiAz=false) · Redis: SingleNode (EnableReplication=false)
# 고가용 모드는 task-scenario-ha.ps1 에서 update-stack 으로 전환
Deploy-Stack -Tier "20" -Name "rds"              -Template "20-data-persistent/rds.yaml" `
    -Parameters @{ EnableMultiAz = "false" }
Deploy-Stack -Tier "20" -Name "redis"            -Template "20-data-persistent/redis.yaml" `
    -Parameters @{ EnableReplication = "false" }
Deploy-Stack -Tier "20" -Name "kinesis"          -Template "20-data-persistent/kinesis.yaml"

# ─────────────────────────────────────────────────
# Tier 30 · Compute Cluster (EKS Control Plane + ECS + Ansible Node)
# ─────────────────────────────────────────────────
# EKS cluster 가장 오래 걸림 (약 10-15 분) · 순차 배포
Deploy-Stack -Tier "30" -Name "eks-cluster"            -Template "30-compute-cluster/eks-cluster.yaml"
Deploy-Stack -Tier "30" -Name "eks-alb-controller-irsa" -Template "30-compute-cluster/eks-alb-controller-irsa.yaml"
Deploy-Stack -Tier "30" -Name "ecs-cluster"            -Template "30-compute-cluster/ecs-cluster.yaml"
Deploy-Stack -Tier "30" -Name "ansible-node"           -Template "30-compute-cluster/ansible-node.yaml"

Write-Step "═══ Base 배포 완료 ═══"
Write-Info "Endpoints · Peering은 각 task 스크립트가 필요 시 배포."
Write-Info "예: .\scripts\aws\2-tasks\task-msa-pods.ps1"

# Azure/GCP 팀에 공유할 정보 출력
if (Get-Command Show-CrossCloudExports -ErrorAction SilentlyContinue) {
    Show-CrossCloudExports
}

Show-AllStacks
