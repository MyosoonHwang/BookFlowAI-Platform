# BOOKFLOW · task-forecast-down · GCP VPN destroy
#   주의: TGW 는 task-auth-pod 과 공유

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-forecast-down · GCP VPN destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

Write-Warn "vpn-site-to-site stack 전체 destroy (Azure + GCP 모두 포함) · Azure 만 유지하려면 task-auth-pod 다시 실행"
Remove-StackSafe -Tier "60" -Name "vpn-site-to-site"

if (-not (Test-Stack -Name "vpn-site-to-site" -Tier "60")) {
    Write-Info "TGW destroy (다른 cross-cloud 작업 없음 가정)"
    Remove-StackSafe -Tier "60" -Name "tgw"
} else {
    Write-Info "TGW 유지 (다른 task 사용 중)"
}

Write-Step "═══ task-forecast-down 완료 ═══"
