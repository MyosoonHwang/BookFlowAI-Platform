# BOOKFLOW · task-publisher · Publisher ASG + ECS inventory-api + Tier 50 (External ALB + WAF)
#   대상: Publisher 채널 (출판사 페이지 · 재고 조회 API)
#   전제: base-up.ps1 + task-data.ps1 (inventory-api 가 RDS read)
#   소요: ~12분 (ALB + WAF + ECS + ASG)
#   비용: ~$1.70/일 (ALB $0.55 + Publisher ASG t3.micro × 2 + Fargate inventory-api + WAF)
#
#   순서:
#     1. alb-external (ALB + 3 Target Groups + Listeners)
#     2. waf (WAFv2 + ALB association)
#     3. publisher-asg (TargetGroupArn = publisher-blue-tg-arn 주입)
#     4. ecs-inventory-api (TargetGroupArn = inventory-api-tg-arn 주입)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-publisher · External ALB + WAF + Publisher + inventory-api ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

if (-not (Test-Stack -Name "vpc-egress" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "rds" -Tier "20")) {
    Write-Warn "RDS 미배포 · inventory-api 가 DB 접속 필요 · task-data.ps1 권장"
}

# ─── 1. External ALB + Target Groups (Tier 50) ───
Deploy-Stack -Tier "50" -Name "alb-external" -Template "50-network-traffic/alb-external.yaml"

# ─── 2. WAFv2 + ALB Association (Tier 50) ───
Deploy-Stack -Tier "50" -Name "waf"          -Template "50-network-traffic/waf.yaml"

# ─── 3. ALB 생성 후 Target Group ARN 조회 ───
$prefix = $env:BOOKFLOW_STACK_PREFIX
$blueTgArn = aws cloudformation describe-stacks --stack-name "$prefix-50-alb-external" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`PublisherBlueTgArn`].OutputValue' --output text
$inventoryTgArn = aws cloudformation describe-stacks --stack-name "$prefix-50-alb-external" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`InventoryApiTgArn`].OutputValue' --output text

Write-Info "Publisher Blue TG: $blueTgArn"
Write-Info "Inventory API TG : $inventoryTgArn"

# ─── 4. Publisher ASG (Blue TG 연결) ───
Deploy-Stack -Tier "40" -Name "publisher-asg" -Template "40-compute-runtime/publisher-asg.yaml" `
    -Parameters @{ TargetGroupArn = $blueTgArn }

# ─── 5. ECS inventory-api (Inventory TG 연결) ───
Deploy-Stack -Tier "40" -Name "ecs-inventory-api" -Template "40-compute-runtime/ecs-inventory-api.yaml" `
    -Parameters @{ TargetGroupArn = $inventoryTgArn }

Write-Step "═══ task-publisher 완료 ═══"
Write-Info  "ALB DNS:"
aws cloudformation describe-stacks --stack-name "$prefix-50-alb-external" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`AlbDnsName`].OutputValue' --output text
