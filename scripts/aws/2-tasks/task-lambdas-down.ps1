# BOOKFLOW · task-lambdas-down · 7 Lambdas + EventBridge + Kinesis ESM + API Gateway destroy
#   주의: pos-ingestor Lambda 가 Kinesis ESM 으로 stream 사용 중이면 ESM 자동 detach
#   Kinesis stream 자체는 task-data-down 에서 삭제

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-lambdas-down · SAM stack destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# SAM transform stack 단일 destroy (모든 Lambda · EventBridge · Kinesis ESM · API Gateway 일괄 제거)
Remove-StackSafe -Tier "99" -Name "lambdas"

Write-Step "═══ task-lambdas-down 완료 ═══"
