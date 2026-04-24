# BOOKFLOW · HA 전환 revert · 구축 모드 (Single-AZ · SingleNode) 로 복귀
#   시나리오 테스트 후 비용 절감 위해 호출

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")

Write-Step "═══ HA revert · Single-AZ + SingleNode 복귀 ═══"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패"
    exit 1
}

Deploy-Stack -Tier "20" -Name "rds"   -Template "20-data-persistent/rds.yaml" `
    -Parameters @{ EnableMultiAz = "false" }

Deploy-Stack -Tier "20" -Name "redis" -Template "20-data-persistent/redis.yaml" `
    -Parameters @{ EnableReplication = "false" }

Write-Step "═══ Revert 완료 ═══"
