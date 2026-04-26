# BOOKFLOW · task-full-stack-down · 모든 task 자원 destroy (역순)
#   대상: 통합 시연 후 정리 · base 는 유지 (base-down.ps1 으로 base 도 정리)
#   순서: lambdas/glue → publisher → etl → msa-pods → data → cross-cloud → client-vpn

. (Join-Path $PSScriptRoot "..\_lib\common.ps1")

Write-Step "═══ task-full-stack-down · 모든 task 자원 destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 역순 destroy
& (Join-Path $PSScriptRoot "task-glue-down.ps1")
& (Join-Path $PSScriptRoot "task-lambdas-down.ps1")
& (Join-Path $PSScriptRoot "task-publisher-down.ps1")
& (Join-Path $PSScriptRoot "task-etl-streaming-down.ps1")
& (Join-Path $PSScriptRoot "task-rds-seed-down.ps1")
& (Join-Path $PSScriptRoot "task-msa-pods-down.ps1")
& (Join-Path $PSScriptRoot "task-data-down.ps1")
& (Join-Path $PSScriptRoot "task-client-vpn-down.ps1")
& (Join-Path $PSScriptRoot "task-forecast-down.ps1")
& (Join-Path $PSScriptRoot "task-auth-pod-down.ps1")

Write-Step "═══ task-full-stack-down 완료 ═══"
Write-Info "base (Tier 10 + Tier 30 ECS shell + Ansible Node) 는 유지"
Write-Info "base 까지 destroy 하려면: .\scripts\aws\1-daily\base-down.ps1"
