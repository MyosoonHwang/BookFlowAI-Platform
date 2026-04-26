# BOOKFLOW · 매일 아침 09:00 · Base 최소 인프라 (running cost 최소화)
#   Tier 00 영구 자원은 이미 있다고 가정 (phase0-foundation.ps1 1회 실행 완료)
#
#   올리는 것 (최소):
#     Tier 10 (VPC 5 + CGW + Route 53)            ← 무료
#     Tier 30 ECS Cluster (껍데기)                  ← 무료 (Task 없으면 과금 0)
#     Tier 30 ALB Controller IRSA Role             ← 무료 (IAM)
#     Tier 30 Ansible Node (Ubuntu 24 t3.nano)    ← ~$1/월 (RDS seed · Glue ops 용)
#
#   올리지 않는 것 (각 task 스크립트가 필요 시 deploy):
#     Tier 20 (RDS/Redis/Kinesis)                  → task-data.ps1
#     Tier 30 EKS Cluster                          → task-msa-pods.ps1
#     Tier 40 EKS Nodegroup + Addons + endpoints   → task-msa-pods.ps1
#     Tier 40 ECS sims + endpoints-sales-data      → task-etl-streaming.ps1
#     Tier 40 Publisher ASG + ECS inventory-api    → task-publisher.ps1
#     Tier 50 NAT + ALB + WAF                      → task-publisher.ps1 (또는 task-auth-pod)
#     Tier 60 TGW + VPN                            → task-auth-pod / task-forecast
#
#   통합 시연: task-full-stack.ps1 (모두 한방에 deploy)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")
. (Join-Path $PSScriptRoot "..\utils\show-cross-cloud-exports.ps1" -ErrorAction SilentlyContinue)

Write-Step "═══ 매일 아침 · Base 최소 인프라 ═══"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패"
    exit 1
}

# ─────────────────────────────────────────────────
# Tier 10 · Network Core (모두 무료 자원)
# ─────────────────────────────────────────────────
Deploy-Stack -Tier "10" -Name "vpc-bookflow-ai"  -Template "10-network-core/vpc-bookflow-ai.yaml"
Deploy-Stack -Tier "10" -Name "vpc-sales-data"   -Template "10-network-core/vpc-sales-data.yaml"
Deploy-Stack -Tier "10" -Name "vpc-egress"       -Template "10-network-core/vpc-egress.yaml"
Deploy-Stack -Tier "10" -Name "vpc-data"         -Template "10-network-core/vpc-data.yaml"
Deploy-Stack -Tier "10" -Name "vpc-ansible"      -Template "10-network-core/vpc-ansible.yaml"
Deploy-Stack -Tier "10" -Name "customer-gateway" -Template "10-network-core/customer-gateway.yaml"
Deploy-Stack -Tier "10" -Name "route53"          -Template "10-network-core/route53.yaml"

# ─────────────────────────────────────────────────
# Tier 30 · 무료 클러스터 껍데기 + Ansible Node
# ─────────────────────────────────────────────────
# ECS Cluster + ALB IRSA Role 은 자체 비용 없음 · Task/Pod 없으면 과금 0
# Ansible Node 만 약간의 EC2 비용 (t3.nano · ~$1/월)
Deploy-Stack -Tier "30" -Name "ecs-cluster"             -Template "30-compute-cluster/ecs-cluster.yaml"
Deploy-Stack -Tier "30" -Name "ansible-node"            -Template "30-compute-cluster/ansible-node.yaml"

Write-Step "═══ Base 배포 완료 (running cost ~$1/일) ═══"
Write-Info  "필요한 작업 task 스크립트로 추가:"
Write-Info  "  .\scripts\aws\2-tasks\task-data.ps1            (RDS · Redis · Kinesis)"
Write-Info  "  .\scripts\aws\2-tasks\task-msa-pods.ps1        (EKS Cluster + Node Group + endpoints)"
Write-Info  "  .\scripts\aws\2-tasks\task-etl-streaming.ps1   (ECS sims + endpoints)"
Write-Info  "  .\scripts\aws\2-tasks\task-publisher.ps1       (Publisher ASG + ALB + WAF + inventory-api)"
Write-Info  "  .\scripts\aws\2-tasks\task-auth-pod.ps1        (NAT + Azure VPN)"
Write-Info  "  .\scripts\aws\2-tasks\task-forecast.ps1        (GCP VPN)"
Write-Info  "  .\scripts\aws\2-tasks\task-rds-seed.ps1        (Ansible playbook)"
Write-Info  "  .\scripts\aws\2-tasks\task-full-stack.ps1      (위 task 전부 한방에)"

# Azure/GCP 팀 공유용 출력
if (Get-Command Show-CrossCloudExports -ErrorAction SilentlyContinue) {
    Show-CrossCloudExports
}

Show-AllStacks
