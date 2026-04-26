# BOOKFLOW · task-auth-pod-down · NAT + Azure VPN destroy
#   주의: TGW 는 task-forecast 와 공유 · 다른 VPN 없을 때만 destroy

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-auth-pod-down · Azure VPN + NAT destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# vpn-site-to-site stack 자체에 GCP VPN 도 있을 수 있음 (Conditions)
# Azure 만 disable: parameter override 로 update 하는 게 더 safe
# 하지만 단순화 위해 stack 전체 destroy (task-forecast 도 영향)
Write-Warn "vpn-site-to-site stack 전체 destroy (Azure + GCP 모두) · GCP 만 유지하려면 task-forecast 다시 실행"
Remove-StackSafe -Tier "60" -Name "vpn-site-to-site"

# TGW 는 task-forecast 와 공유 · 다른 사용자 없을 때만 destroy
if (-not (Test-Stack -Name "vpn-site-to-site" -Tier "60")) {
    Write-Info "TGW destroy (다른 cross-cloud 작업 없음 가정)"
    Remove-StackSafe -Tier "60" -Name "tgw"
} else {
    Write-Info "TGW 유지 (다른 task 사용 중)"
}

# Tier 50 NAT
Remove-StackSafe -Tier "50" -Name "nat-gateway"

# endpoints-bookflow-ai 는 task-msa-pods 와 공유 · destroy 안 함
Write-Info "endpoints-bookflow-ai 는 task-msa-pods 와 공유 · 유지"

Write-Step "═══ task-auth-pod-down 완료 ═══"
