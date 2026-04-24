# BOOKFLOW · 시나리오 HA 전환 · RDS Multi-AZ + Redis ReplicationGroup
#   base-up 상태 (Single-AZ · Single-node) 에서 호출
#   update-stack 으로 parameter 만 toggle
#   Rollback: task-scenario-ha-revert.ps1

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")

Write-Step "═══ 시나리오 HA 전환 · RDS Multi-AZ + Redis Replication ═══"
Write-Info  "주의: Redis SingleNode → ReplicationGroup 은 resource replacement (cache 소실)"
Write-Info  "      RDS Multi-AZ 전환은 in-place modify (약 5-10 분)"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패"
    exit 1
}

# RDS: Multi-AZ on
Deploy-Stack -Tier "20" -Name "rds"   -Template "20-data-persistent/rds.yaml" `
    -Parameters @{ EnableMultiAz = "true" }

# Redis: Replication on (기존 CacheCluster → ReplicationGroup · replace)
Deploy-Stack -Tier "20" -Name "redis" -Template "20-data-persistent/redis.yaml" `
    -Parameters @{ EnableReplication = "true" }

Write-Step "═══ HA 전환 완료 · failover 테스트 준비 ═══"
Write-Info "Revert: .\scripts\aws\2-tasks\task-scenario-ha-revert.ps1"
