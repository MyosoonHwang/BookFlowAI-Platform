# BOOKFLOW · task-auth-pod · Auth Pod 작업용 (NAT + Azure VPN + Secrets endpoints)
#   대상: 영헌 (Auth Pod 개발 시 · Azure Entra OIDC 통신 필요)
#   전제: base-up.ps1 + task-msa-pods.ps1 (EKS 위에 Pod 배포)
#   소요: ~10분 (NAT + VPN)
#   비용: ~$1.50/일 (NAT $32/월 → 일 $1.07 + VPN)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-auth-pod · NAT + Azure VPN + Secrets endpoints ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "vpc-egress" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "eks-cluster" -Tier "30")) {
    Write-Warn "EKS Cluster 미배포 · Pod 배포 전 task-msa-pods.ps1 필요"
}

# Secrets endpoints (이미 task-msa-pods 가 endpoints-bookflow-ai 올렸으면 skip)
if (-not (Test-Stack -Name "endpoints-bookflow-ai" -Tier "10")) {
    Deploy-Stack -Tier "10" -Name "endpoints-bookflow-ai" -Template "10-network-core/endpoints/endpoints-bookflow-ai.yaml"
}

# Tier 50 NAT (Egress VPC public · Auth Pod outbound to Azure · TGW 활성 시 cross-VPC 전용)
Deploy-Stack -Tier "50" -Name "nat-gateway" -Template "50-network-traffic/nat-gateway.yaml"

# Tier 60 TGW Hub + 4 VPC Attachment (cross-cloud 전용)
Deploy-Stack -Tier "60" -Name "tgw" -Template "60-network-cross-cloud/tgw.yaml"

# Tier 60 Azure VPN (Customer Gateway IP 가 있어야 활성)
#   필요 env var:
#     BOOKFLOW_AZURE_VPN_GW_IP   = 민지에게 받음 (Azure deploy-vpn.sh 의 Active 공인 IP)
#     BOOKFLOW_AZURE_VPN_PSK     = (선택) PSK · 공란이면 AWS 자동 생성
$cgwAzureIp = $env:BOOKFLOW_AZURE_VPN_GW_IP
$azurePsk   = $env:BOOKFLOW_AZURE_VPN_PSK
if ($cgwAzureIp -and $cgwAzureIp -ne "0.0.0.0") {
    # Customer Gateway IP 주입 (Tier 10 customer-gateway update-stack)
    Deploy-Stack -Tier "10" -Name "customer-gateway" -Template "10-network-core/customer-gateway.yaml" `
        -Parameters @{ AzureVpnGatewayIp = $cgwAzureIp }
    # VPN Connection · TGW VPN Attach
    $vpnParams = @{ EnableAzureVpn = "true" }
    if ($azurePsk) { $vpnParams.AzurePresharedKey = $azurePsk }
    Deploy-Stack -Tier "60" -Name "vpn-site-to-site" -Template "60-network-cross-cloud/vpn-site-to-site.yaml" `
        -Parameters $vpnParams

    # 민지에게 전달할 값 출력
    . (Join-Path $PSScriptRoot "..\utils\show-cross-cloud-exports.ps1")
    Show-CrossCloudExports
} else {
    Write-Warn "BOOKFLOW_AZURE_VPN_GW_IP 환경변수 없음 · Azure VPN 미활성"
    Write-Info  "민지에게 Azure VPN GW Active 공인 IP 받아서:"
    Write-Info  '  $env:BOOKFLOW_AZURE_VPN_GW_IP = "203.0.113.10"'
    Write-Info  '  (선택) $env:BOOKFLOW_AZURE_VPN_PSK = "공유한 PSK"'
    Write-Info  '  .\task-auth-pod.ps1'
}

Write-Step "═══ task-auth-pod 완료 ═══"
