# BOOKFLOW · task-etl-streaming · ECS sims (online + offline) + endpoints-sales-data
#   대상: 민지 (POS 시뮬 ETL · Kinesis · Firehose 검증)
#   전제: base-up.ps1 + task-data.ps1 (Kinesis 필요)
#   소요: ~7분
#   비용: ~$0.40/일 (ECS Fargate 0.25v × 2 sims · endpoints 3개)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-etl-streaming · ECS sims + endpoints-sales-data ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "vpc-sales-data" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "kinesis" -Tier "20")) {
    Write-Err "Kinesis 미배포 · task-data.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "ecs-cluster" -Tier "30")) {
    Write-Err "ECS Cluster 미배포 · base-up.ps1 먼저 실행"; exit 1
}

# Sales Data VPC Endpoints (ECR pull · Kinesis put · Private subnet 에서 AWS 서비스 접근)
Deploy-Stack -Tier "10" -Name "endpoints-sales-data" -Template "10-network-core/endpoints/endpoints-sales-data.yaml"

# Peering: Sales sim → External ALB (재고 조회 API 호출 · Slide 6)
Deploy-Stack -Tier "10" -Name "peering-sales-data-egress" -Template "10-network-core/peering/sales-data-egress.yaml"

# ECS sims (image 는 placeholder · CI/CD 가 update-stack 으로 갱신)
Deploy-Stack -Tier "40" -Name "ecs-online-sim"  -Template "40-compute-runtime/ecs-online-sim.yaml"
Deploy-Stack -Tier "40" -Name "ecs-offline-sim" -Template "40-compute-runtime/ecs-offline-sim.yaml"

Write-Step "═══ task-etl-streaming 완료 ═══"
