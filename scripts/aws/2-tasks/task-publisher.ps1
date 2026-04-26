# BOOKFLOW · task-publisher · Publisher ASG + ECS inventory-api + Tier 50 (NAT/ALB/WAF)
#   대상: Publisher 채널 (출판사 페이지 · 재고 조회 API)
#   전제: base-up.ps1 + task-data.ps1 (inventory-api 가 RDS read)
#   소요: ~10분
#   비용: ~$1.20/일 (Publisher ASG t3.small × 2 + Fargate inventory-api + ALB · 추후 WAF)
#
#   ⚠️ Tier 50 (alb-external · waf · nat-gateway) 는 별도 작성 필요 (현재 placeholder)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-publisher · Publisher + inventory-api + (Tier 50) ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "vpc-egress" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "rds" -Tier "20")) {
    Write-Warn "RDS 미배포 · inventory-api 가 DB 접속 필요 · task-data.ps1 권장"
}

# Tier 50 · External ALB + (WAF) · 추후 작성
# Deploy-Stack -Tier "50" -Name "alb-external" -Template "50-network-traffic/alb-external.yaml"
# Deploy-Stack -Tier "50" -Name "waf"          -Template "50-network-traffic/waf.yaml"
Write-Warn "Tier 50 (alb-external · waf) 는 아직 작성 전 · LoadBalancer 미연결 상태로 deploy"

# ECS inventory-api (TargetGroupArn 미지정 → LoadBalancer 미연결)
Deploy-Stack -Tier "40" -Name "ecs-inventory-api" -Template "40-compute-runtime/ecs-inventory-api.yaml"

# Publisher ASG (TargetGroupArn 미지정 → ALB 미연결)
Deploy-Stack -Tier "40" -Name "publisher-asg"     -Template "40-compute-runtime/publisher-asg.yaml"

Write-Step "═══ task-publisher 완료 ═══"
Write-Info  "Tier 50 alb-external 추가 후 update-stack 으로 TargetGroupArn 주입:"
Write-Info  '  Deploy-Stack -Tier "40" -Name "ecs-inventory-api" -Template "..." -Parameters @{ TargetGroupArn = "<arn>" }'
