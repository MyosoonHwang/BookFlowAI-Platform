# BOOKFLOW · task-glue · Tier 99-glue (Catalog + 6 Jobs + Step Functions ETL3)
#   대상: 민지 (ETL3 Raw → Mart 정제 · features 조립)
#   전제:
#     - base-up (S3 buckets via Tier 00)
#     - task-data 권장 (Mart 의 sales_daily_agg 가 RDS 와 같은 day 데이터 비교)
#   소요: ~3분
#   비용: ~$4/월 (Glue Flex DPU · Step Functions free tier)
#
#   동작:
#     1. glue-catalog deploy: Database + 6 Jobs + IAM + BigQuery Connection
#     2. step-functions deploy: ETL3 State Machine (Glue Jobs orchestration)
#     3. forecast-trigger Lambda 의 SF ARN 자동 update (task-lambdas 가 deploy 된 경우)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-glue · Glue Catalog + 6 Jobs + ETL3 Step Functions ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크 (S3 buckets · Tier 00 영구)
$prefix = $env:BOOKFLOW_STACK_PREFIX

# ─── 1. Glue Catalog + Jobs + Connection ───
Deploy-Stack -Tier "99" -Name "glue-catalog"   -Template "99-glue/glue-catalog.yaml"

# ─── 2. Step Functions ETL3 State Machine ───
Deploy-Stack -Tier "99" -Name "step-functions" -Template "99-glue/step-functions.yaml"

# ─── 3. forecast-trigger Lambda 에 SF ARN 자동 주입 (task-lambdas 가 이미 deploy 됐을 때) ───
$sfnArn = aws cloudformation describe-stacks --stack-name "$prefix-99-step-functions" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`Etl3StateMachineArn`].OutputValue' --output text 2>$null

if (Test-Stack -Name "lambdas" -Tier "99") {
    Write-Info "task-lambdas 이미 deploy 됨 → forecast-trigger 에 SF ARN update-stack:"
    Deploy-Stack -Tier "99" -Name "lambdas" -Template "99-serverless/sam-template.yaml" `
        -Capabilities @("CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND", "CAPABILITY_IAM") `
        -Parameters @{ StepFunctionsArn = $sfnArn }
} else {
    Write-Info "task-lambdas 미배포 · 추후 task-lambdas.ps1 실행 시 자동으로 SF ARN 주입됨"
}

Write-Step "═══ task-glue 완료 ═══"
Write-Info  "Glue Jobs 확인:"
Write-Info  "  aws glue get-jobs --query 'Jobs[?starts_with(Name, ``bookflow-``)].Name' --output table"
Write-Info  "ETL3 State Machine 수동 실행:"
Write-Info  "  aws stepfunctions start-execution --state-machine-arn $sfnArn"
