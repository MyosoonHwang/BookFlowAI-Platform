# BOOKFLOW · Tier 00 Foundation Destroy (영구 자원 제거 · 매우 신중)
#   ⚠️ 영구 자원 (KMS · Secrets · S3 · ECR 이미지 · ACM cert · CloudTrail logs 등)
#   ⚠️ 한 번 destroy 하면 복구 불가 또는 매우 복잡 (S3 객체 영구 삭제 · KMS deletion pending 7-30일)
#   사용 시점: 프로젝트 완료 후 또는 학기 종료 후 계정 정리

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ Tier 00 Foundation Destroy (영구 자원!) ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 강력 confirmation
Write-Host ""
Write-Host "⚠️  주의: 영구 자원 제거 ⚠️" -ForegroundColor Red
Write-Host "  - KMS CMK 2개 → 7-30일 deletion pending" -ForegroundColor Yellow
Write-Host "  - Secrets Manager → 7-30일 deletion pending (force-delete-without-recovery 옵션)" -ForegroundColor Yellow
Write-Host "  - S3 buckets → DeletionPolicy: Retain (CFN 으로 못 지움 · 수동 삭제 필요)" -ForegroundColor Yellow
Write-Host "  - ECR repositories → 이미지 제거 후 가능" -ForegroundColor Yellow
Write-Host "  - ACM Certificate → IN_USE 시 거부 (Client VPN 등 의존)" -ForegroundColor Yellow
Write-Host "  - CloudTrail → S3 logs 영구 보존 (Retain)" -ForegroundColor Yellow
Write-Host ""
Write-Host "확인 입력 (정확히 'WIPE FOUNDATION' 타입):" -ForegroundColor Red
$confirm = Read-Host
if ($confirm -ne "WIPE FOUNDATION") {
    Write-Warn "취소됨"
    exit 0
}

# 사전 작업: ECR 이미지 비우기 권장 (CFN 이 못 지움)
Write-Warn "사전 작업 권장 (CFN 이 처리 못 하는 것):"
Write-Warn "  1. ECR 이미지 비우기:"
Write-Warn "     foreach repo: aws ecr batch-delete-image --repository-name <repo> --image-ids ..."
Write-Warn "  2. S3 버킷 비우기 + 수동 삭제 (DeletionPolicy Retain):"
Write-Warn "     foreach bucket: aws s3 rm s3://<bucket> --recursive ; aws s3api delete-bucket --bucket <bucket>"
Write-Warn ""

Write-Host "위 작업 완료했나요? (y/N): " -NoNewline -ForegroundColor Yellow
$preDone = Read-Host
if ($preDone -ne "y") { Write-Warn "취소됨 · 위 작업 먼저 수행 후 재실행"; exit 0 }

# 역순 destroy (의존성 역방향)
# 배포 순서: iam → kms → parameter-store → secrets → acm → ecr → codestar-connection → s3 → cloudtrail → cloudwatch
# Destroy 역순: cloudwatch → cloudtrail → s3 → codestar → ecr → acm → secrets → param → kms → iam
Remove-StackSafe -Tier "00" -Name "cloudwatch"
Remove-StackSafe -Tier "00" -Name "cloudtrail"
Remove-StackSafe -Tier "00" -Name "s3"
Remove-StackSafe -Tier "00" -Name "codestar-connection"
Remove-StackSafe -Tier "00" -Name "ecr"
Remove-StackSafe -Tier "00" -Name "acm"
Remove-StackSafe -Tier "00" -Name "secrets"
Remove-StackSafe -Tier "00" -Name "parameter-store"
Remove-StackSafe -Tier "00" -Name "kms"
Remove-StackSafe -Tier "00" -Name "iam"

Write-Step "═══ Tier 00 Destroy 완료 ═══"
Write-Warn "사후 확인:"
Write-Warn "  - KMS keys → aws kms list-keys (PendingDeletion 상태 확인)"
Write-Warn "  - Secrets → aws secretsmanager list-secrets (Scheduled deletion)"
Write-Warn "  - S3 buckets → aws s3 ls (수동 삭제 필요할 수 있음)"
