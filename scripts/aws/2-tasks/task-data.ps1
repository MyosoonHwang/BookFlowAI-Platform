# BOOKFLOW · task-data · Tier 20 (RDS PostgreSQL · Redis · Kinesis + Firehose)
#   전제: base-up.ps1 완료 (Tier 10 VPC 필요)
#   소요: ~12분 (RDS 가장 오래)
#   비용: ~$1.30/일 (RDS Single-AZ · Redis SingleNode · Kinesis 5 shards)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-data · RDS + Redis + Kinesis ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크 (Tier 10)
if (-not (Test-Stack -Name "vpc-data" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"
    exit 1
}

# 구축 모드 (Single-AZ · 저비용) · HA 전환은 task-scenario-ha.ps1
Deploy-Stack -Tier "20" -Name "rds"     -Template "20-data-persistent/rds.yaml" `
    -Parameters @{ EnableMultiAz = "false" }
Deploy-Stack -Tier "20" -Name "redis"   -Template "20-data-persistent/redis.yaml" `
    -Parameters @{ EnableReplication = "false" }
Deploy-Stack -Tier "20" -Name "kinesis" -Template "20-data-persistent/kinesis.yaml"

Write-Step "═══ task-data 완료 ═══"
