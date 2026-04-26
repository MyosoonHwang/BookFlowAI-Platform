# BOOKFLOW · task-client-vpn-down · Client VPN Endpoint destroy

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-client-vpn-down · Client VPN Endpoint destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

Remove-StackSafe -Tier "60" -Name "client-vpn"

Write-Step "═══ task-client-vpn-down 완료 ═══"
Write-Info "활성 Client VPN connection 이 있을 시 자동 disconnect"
