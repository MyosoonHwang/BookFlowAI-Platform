# BOOKFLOW · task-forecast · GCP VPN (forecast-svc Pod 가 Vertex AI Endpoint 통신)
#   대상: 우혁 (Vertex AI 통신 검증)
#   전제: base-up.ps1 + task-msa-pods.ps1 (forecast-svc EKS Pod 배포 후)
#   소요: ~5분 (VPN tunnel 설정)
#   비용: ~$1.50/일 (Site-to-Site VPN $36/월)
#
#   ⚠️ Tier 60 vpn-site-to-site 는 별도 작성 필요

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-forecast · GCP HA VPN ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "customer-gateway" -Tier "10")) {
    Write-Err "Customer Gateway 미배포 · base-up.ps1 먼저 실행"; exit 1
}

# Tier 60 TGW Hub + 4 VPC Attachment (cross-cloud 전용)
Deploy-Stack -Tier "60" -Name "tgw" -Template "60-network-cross-cloud/tgw.yaml"

# Tier 60 GCP HA VPN (Customer Gateway IP 가 있어야 활성)
#   필요 env var:
#     BOOKFLOW_GCP_VPN_GW_IP   = 우혁에게 받음 (GCP HA VPN 4 IPs 중 1개)
#     BOOKFLOW_GCP_VPN_PSK     = (선택) GCP terraform.tfvars vpn_shared_secret
$cgwGcpIp = $env:BOOKFLOW_GCP_VPN_GW_IP
$gcpPsk   = $env:BOOKFLOW_GCP_VPN_PSK
if ($cgwGcpIp -and $cgwGcpIp -ne "0.0.0.0") {
    Deploy-Stack -Tier "10" -Name "customer-gateway" -Template "10-network-core/customer-gateway.yaml" `
        -Parameters @{ GcpHaVpnIp = $cgwGcpIp }
    $vpnParams = @{ EnableGcpVpn = "true" }
    if ($gcpPsk) { $vpnParams.GcpPresharedKey = $gcpPsk }
    Deploy-Stack -Tier "60" -Name "vpn-site-to-site" -Template "60-network-cross-cloud/vpn-site-to-site.yaml" `
        -Parameters $vpnParams

    # 우혁에게 전달할 값 출력
    . (Join-Path $PSScriptRoot "..\utils\show-cross-cloud-exports.ps1")
    Show-CrossCloudExports
} else {
    Write-Warn "BOOKFLOW_GCP_VPN_GW_IP 환경변수 없음 · GCP VPN 미활성"
    Write-Info  "우혁에게 GCP HA VPN 4 IPs 중 1개 받아서 (FOUR_IPS_REDUNDANCY):"
    Write-Info  '  $env:BOOKFLOW_GCP_VPN_GW_IP = "203.0.113.20"'
    Write-Info  '  (선택) $env:BOOKFLOW_GCP_VPN_PSK = "공유한 PSK"'
    Write-Info  '  .\task-forecast.ps1'
}

Write-Step "═══ task-forecast 완료 ═══"
