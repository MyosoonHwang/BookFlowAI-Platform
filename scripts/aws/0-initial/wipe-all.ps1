# BOOKFLOW · WIPE ALL · 모든 자원 제거 (Tier 00 영구 포함)
#   ⚠️ 가장 강력한 destroy · 프로젝트 완전 종료 시 사용
#   순서: base-down (Tier 10-60) → phase0-foundation-down (Tier 00 영구)

. (Join-Path $PSScriptRoot "..\_lib\common.ps1")

Write-Step "═══ WIPE ALL · 모든 BOOKFLOW 자원 제거 ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

Write-Host ""
Write-Host "⚠️  최종 경고 ⚠️" -ForegroundColor Red
Write-Host "  이 스크립트는 BOOKFLOW 프로젝트의 모든 AWS 자원을 제거합니다." -ForegroundColor Red
Write-Host ""
Write-Host "  포함:" -ForegroundColor Yellow
Write-Host "    - Tier 10-60 (VPC · RDS · EKS · ECS · ALB · TGW · VPN · etc.)"
Write-Host "    - Tier 00 영구 자원 (KMS · Secrets · S3 · ECR · ACM · CloudTrail)"
Write-Host ""
Write-Host "  복구 가능?" -ForegroundColor Yellow
Write-Host "    - Tier 10-60: phase0 Tier 00 후 base-up + task 재실행으로 복구"
Write-Host "    - Tier 00 KMS · Secrets: 7-30일 deletion pending (취소 가능)"
Write-Host "    - Tier 00 S3 객체: 영구 삭제 (CloudTrail 로그 등 손실)"
Write-Host "    - Tier 00 ECR 이미지: 영구 삭제"
Write-Host ""
Write-Host "확인 입력 (정확히 'WIPE EVERYTHING' 타입):" -ForegroundColor Red
$confirm = Read-Host
if ($confirm -ne "WIPE EVERYTHING") {
    Write-Warn "취소됨"
    exit 0
}

# Step 1: Tier 10-60 destroy (base-down)
Write-Step "Step 1/2 · Tier 10-60 destroy (base-down.ps1)"
& (Join-Path $PSScriptRoot "..\1-daily\base-down.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Err "base-down 실패 · 수동 확인 후 다시 시도"
    exit 1
}

# Step 2: Tier 00 destroy
Write-Step "Step 2/2 · Tier 00 영구 자원 destroy (phase0-foundation-down.ps1)"
& (Join-Path $PSScriptRoot "phase0-foundation-down.ps1")

Write-Step "═══ WIPE ALL 완료 ═══"
Write-Warn "수동 사후 확인 필요:"
Write-Warn "  aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, ``bookflow-``)]' --output table"
Write-Warn "  aws s3 ls | grep bookflow"
Write-Warn "  aws ecr describe-repositories | grep bookflow"
