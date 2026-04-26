# BOOKFLOW · task-glue-down · Glue Catalog · 6 Jobs · Step Functions destroy
#   주의: forecast-trigger Lambda 의 STEP_FN_ARN 환경변수가 invalid 됨 (placeholder 응답)

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-glue-down · Glue + Step Functions destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# step-functions 먼저 (glue-catalog Import 사용 중)
Remove-StackSafe -Tier "99" -Name "step-functions"

# glue-catalog (Database + 6 Jobs + IAM + BigQuery Connection)
Remove-StackSafe -Tier "99" -Name "glue-catalog"

Write-Step "═══ task-glue-down 완료 ═══"
Write-Info "forecast-trigger Lambda 의 SF ARN 환경변수가 invalid 됨"
Write-Info "  필요 시 task-lambdas 재실행으로 STEP_FN_ARN 환경변수 빈 값으로 reset"
