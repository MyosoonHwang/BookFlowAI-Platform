# BOOKFLOW · task-data-down · Tier 20 destroy (Kinesis · Redis · RDS)
#   주의: RDS DeletionPolicy=Delete 라 데이터 영구 삭제 (BackupRetentionPeriod=0)

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-data-down · Tier 20 destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 역순 destroy
Remove-StackSafe -Tier "20" -Name "kinesis"
Remove-StackSafe -Tier "20" -Name "redis"
Remove-StackSafe -Tier "20" -Name "rds"

Write-Step "═══ task-data-down 완료 ═══"
