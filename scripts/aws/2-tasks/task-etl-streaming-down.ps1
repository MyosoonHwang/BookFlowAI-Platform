# BOOKFLOW · task-etl-streaming-down · ECS sims + endpoints + peering destroy

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-etl-streaming-down · ECS sims destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# Tier 40 ECS sims
Remove-StackSafe -Tier "40" -Name "ecs-offline-sim"
Remove-StackSafe -Tier "40" -Name "ecs-online-sim"

# Tier 10 peering + endpoints
Remove-StackSafe -Tier "10" -Name "peering-sales-data-egress"
Remove-StackSafe -Tier "10" -Name "endpoints-sales-data"

Write-Step "═══ task-etl-streaming-down 완료 ═══"
