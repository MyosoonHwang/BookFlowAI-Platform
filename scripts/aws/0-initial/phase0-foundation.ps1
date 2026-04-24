# BOOKFLOW · Tier 00 Foundation Deploy (Day 0 1회만)
# 영구 자원 (IAM · KMS · S3 · Secrets · ACM · ParameterStore · R53 · CloudTrail · CloudWatch)
#
# 사용: .\scripts\aws\0-initial\phase0-foundation.ps1

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ Phase 0 · Foundation Deploy (영구 자원 · Day 0 1회) ═══"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패 · aws configure 먼저 실행"
    exit 1
}

# ─────────────────────────────────────────────────────────────
# 배포 순서 (의존성 기반) · 8개 stack
# ─────────────────────────────────────────────────────────────
#   1. iam             (GHA OIDC + GHA Role · GhaDeployRole 등)
#   2. kms             (CMK × 2 · EKS envelope + CloudTrail)
#   3. parameter-store (공통 설정값 · 독립)
#   4. secrets         (Secrets Manager skeleton · 독립)
#   5. acm             (Client VPN cert · skeleton · 독립)
#   6. s3              (6 bucket · kms Import)
#   7. cloudtrail      (Trail · s3 + kms Import)
#   8. cloudwatch      (Log Groups · Alarm SNS · 독립)
#
# ※ route53 (Private Hosted Zone)은 VPC 필요 → 20a-network-core로 이관
# ※ Lambda Log Groups는 cloudwatch에 미리 선언 (SAM이 재사용)
# ─────────────────────────────────────────────────────────────

Deploy-Stack -Tier "00" -Name "iam"                 -Template "00-foundation/iam.yaml"
Deploy-Stack -Tier "00" -Name "kms"                 -Template "00-foundation/kms.yaml"
Deploy-Stack -Tier "00" -Name "parameter-store"     -Template "00-foundation/parameter-store.yaml"
Deploy-Stack -Tier "00" -Name "secrets"             -Template "00-foundation/secrets.yaml"
Deploy-Stack -Tier "00" -Name "acm"                 -Template "00-foundation/acm.yaml"
Deploy-Stack -Tier "00" -Name "ecr"                 -Template "00-foundation/ecr.yaml"
Deploy-Stack -Tier "00" -Name "codestar-connection" -Template "00-foundation/codestar-connection.yaml"
Deploy-Stack -Tier "00" -Name "s3"                  -Template "00-foundation/s3.yaml"
Deploy-Stack -Tier "00" -Name "cloudtrail"          -Template "00-foundation/cloudtrail.yaml"
Deploy-Stack -Tier "00" -Name "cloudwatch"          -Template "00-foundation/cloudwatch.yaml"

Write-Warn "⚠ CodeStar Connection 은 PENDING 상태로 생성됨"
Write-Warn "   Console > Developer Tools > Settings > Connections 에서 수동 Activate 필요"

Write-Step "═══ Tier 00 Foundation 배포 완료 ═══"
Show-AllStacks
