# BOOKFLOW · task-lambdas · Tier 99-serverless (7 Lambdas + EventBridge + Kinesis ESM + API Gateway)
#   대상: ETL · forecast · auth secret 작업 (모든 Lambda 한방에)
#   전제:
#     - base-up (VPC + Ansible Node)
#     - task-data (Kinesis · RDS · Secrets) — pos-ingestor / spike-detect 가 사용
#     - task-msa-pods (peering bookflow-ai-data) — VPC Lambda → RDS 경로
#   소요: ~3분 (Lambda 7개 동시 deploy)
#   비용: ~$0/월 (모두 프리티어 내 · pos-ingestor Kinesis ESM 도 경량)
#
#   trigger 활성:
#     - cron 5종: aladin-sync · event-sync · sns-gen · spike-detect · forecast-trigger
#     - Kinesis ESM: pos-ingestor (← Tier 20 kinesis stream)
#     - API Gateway HTTP: secret-forwarder (← Azure Function 호출)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-lambdas · 7 Lambdas SAM deploy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "vpc-bookflow-ai" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "kinesis" -Tier "20")) {
    Write-Err "Kinesis 미배포 · task-data.ps1 먼저 실행 (pos-ingestor 가 ESM 으로 사용)"; exit 1
}
if (-not (Test-Stack -Name "rds" -Tier "20")) {
    Write-Warn "RDS 미배포 · pos-ingestor / spike-detect 동작 안함"
}
if (-not (Test-Stack -Name "peering-bookflow-ai-data" -Tier "10")) {
    Write-Warn "peering bookflow-ai-data 미배포 · pos-ingestor / spike-detect → RDS 경로 단절 · task-msa-pods.ps1 권장"
}

# Step Functions ARN 조회 (Tier 99-glue 후 존재)
$prefix = $env:BOOKFLOW_STACK_PREFIX
$sfnArn = aws cloudformation describe-stacks --stack-name "$prefix-99-glue-jobs" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`Etl3StateMachineArn`].OutputValue' --output text 2>$null
if (-not $sfnArn -or $sfnArn -eq "None") { $sfnArn = "" }

# SAM transform → CAPABILITY_AUTO_EXPAND 필수
$params = @{}
if ($sfnArn) { $params.StepFunctionsArn = $sfnArn }
Deploy-Stack -Tier "99" -Name "lambdas" -Template "99-serverless/sam-template.yaml" `
    -Capabilities @("CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND", "CAPABILITY_IAM") `
    -Parameters $params

Write-Step "═══ task-lambdas 완료 ═══"
Write-Info  "Lambda 동작 확인:"
Write-Info  "  aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `bookflow-`)].FunctionName' --output table"
Write-Info  "secret-forwarder API URL:"
$apiUrl = aws cloudformation describe-stacks --stack-name "$prefix-99-lambdas" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`SecretForwarderApiUrl`].OutputValue' --output text 2>$null
Write-Info  "  $apiUrl/secret"
