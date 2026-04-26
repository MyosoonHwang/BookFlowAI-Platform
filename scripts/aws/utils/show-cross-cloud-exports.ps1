# BOOKFLOW · show-cross-cloud-exports
# 매일 base-up 후 자동 호출 또는 task-auth-pod / task-forecast 후 수동 호출
#   AWS 측 자원 정보 → Azure (민지) · GCP (우혁) 팀 전달용
#   결과: console + ./exports/aws-YYYY-MM-DD.txt (.gitignored)

. (Join-Path $PSScriptRoot "..\_lib\common.ps1")

function Show-CrossCloudExports {
    $today = Get-Date -Format "yyyy-MM-dd"
    $time = Get-Date -Format "HH:mm"
    $exportDir = Join-Path (Get-Location) "exports"
    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir | Out-Null }
    $outFile = Join-Path $exportDir "aws-$today.txt"

    $prefix = $env:BOOKFLOW_STACK_PREFIX
    $region = $env:AWS_REGION

    # Helper: stack output 조회 (없으면 빈 문자열)
    function Get-Output($stackName, $outputKey) {
        $val = aws cloudformation describe-stacks --stack-name "$prefix-$stackName" `
            --region $region --query "Stacks[0].Outputs[?OutputKey=='$outputKey'].OutputValue" `
            --output text 2>$null
        if ($LASTEXITCODE -ne 0 -or $val -eq "None") { return "" }
        return $val
    }

    $output = @()
    $output += "================================================="
    $output += "  BOOKFLOW · AWS 측 cross-cloud 전달값"
    $output += "  $today $time · region $region"
    $output += "================================================="
    $output += ""

    # ─── VPC CIDR (Azure VNet · GCP VPC 와 무겹침 확인용) ───
    $output += "▶ VPC CIDR (Azure 172.16.0.0/16 · GCP 192.168.0.0/16 와 무겹침)"
    $output += "  BookFlow AI VPC : 10.0.0.0/16"
    $output += "  Sales Data VPC  : 10.1.0.0/16"
    $output += "  Egress VPC      : 10.2.0.0/16"
    $output += "  Data VPC        : 10.3.0.0/16"
    $output += "  Ansible VPC     : 10.4.0.0/16"
    $output += ""

    # ─── TGW (Tier 60 활성 시) ───
    $tgwId = Get-Output "60-tgw" "TgwId"
    if ($tgwId) {
        $tgwAsn = Get-Output "60-tgw" "TgwAsn"
        $output += "▶ Transit Gateway (Phase 3+ active)"
        $output += "  TGW ID  : $tgwId"
        $output += "  TGW ASN : $tgwAsn"
        $output += ""
    }

    # ─── Azure VPN (vpn-site-to-site Azure deploy 후) ───
    $azureVpnId = Get-Output "60-vpn-site-to-site" "AzureVpnConnectionId"
    if ($azureVpnId) {
        $output += "▶ Azure 팀 (민지) 전달값 · scripts/azure/2-tasks/vpn-connect.sh 입력용"
        $output += "  AWS Customer Gateway IP   : $(Get-CgwIp 'azure')"
        $tunnelInfo = aws ec2 describe-vpn-connections --vpn-connection-ids $azureVpnId --region $region `
            --query 'VpnConnections[0].VgwTelemetry[].{IP:OutsideIpAddress,Status:Status}' --output json | ConvertFrom-Json
        for ($i=0; $i -lt $tunnelInfo.Count; $i++) {
            $output += ("  AWS Tunnel{0} Outside IP   : {1} · status: {2}" -f ($i+1), $tunnelInfo[$i].IP, $tunnelInfo[$i].Status)
        }
        $output += "  AWS Tunnel BGP Inside CIDR: 169.254.100.0/30 (Tunnel1) · 169.254.100.4/30 (Tunnel2)"
        $output += "  AWS TGW BGP ASN           : $(Get-Output '60-tgw' 'TgwAsn')"
        $output += "  Pre-Shared Key            : aws ec2 describe-vpn-connections --vpn-connection-ids $azureVpnId --query 'VpnConnections[0].Options.TunnelOptions[].PreSharedKey'"
        $output += ""
    }

    # ─── GCP VPN (vpn-site-to-site GCP deploy 후) ───
    $gcpVpnId = Get-Output "60-vpn-site-to-site" "GcpVpnConnectionId"
    if ($gcpVpnId) {
        $output += "▶ GCP 팀 (우혁) 전달값 · infra/gcp/20-network-daily/terraform.tfvars 입력용"
        $output += "  AWS Customer Gateway IP   : $(Get-CgwIp 'gcp')"
        $tunnelInfo = aws ec2 describe-vpn-connections --vpn-connection-ids $gcpVpnId --region $region `
            --query 'VpnConnections[0].VgwTelemetry[].{IP:OutsideIpAddress,Status:Status}' --output json | ConvertFrom-Json
        $output += "  aws_peer_ips = [  # terraform.tfvars"
        for ($i=0; $i -lt $tunnelInfo.Count; $i++) {
            $output += ("    `"{0}`",  # Tunnel{1}" -f $tunnelInfo[$i].IP, ($i+1))
        }
        $output += "  ]"
        $output += "  aws_tgw_bgp_asn = $(Get-Output '60-tgw' 'TgwAsn')"
        $output += "  vpn_shared_secret = `"<aws ec2 describe-vpn-connections ...PreSharedKey>`""
        $output += ""
    }

    # ─── 영구 자원 (Day 0) ───
    $output += "▶ Tier 00 영구 자원 (참고)"
    $output += "  Account ID : $env:BOOKFLOW_ACCOUNT_ID"
    $output += "  Region     : $region"
    $output += ""

    $output += "================================================="
    $output += "→ 위 내용을 Slack/KakaoTalk 으로 민지·우혁에게 공유"
    $output += "→ exports/aws-$today.txt 에 저장됨 (gitignored)"
    $output += "================================================="

    # 콘솔 출력 + 파일 저장
    $output | ForEach-Object { Write-Host $_ }
    $output | Set-Content -Path $outFile -Encoding UTF8
    Write-Host ""
    Write-Host "→ 저장: $outFile" -ForegroundColor Cyan
}

function Get-CgwIp($provider) {
    $prefix = $env:BOOKFLOW_STACK_PREFIX
    $region = $env:AWS_REGION
    if ($provider -eq "azure") {
        $cgwId = aws cloudformation describe-stacks --stack-name "$prefix-10-customer-gateway" --region $region `
            --query 'Stacks[0].Outputs[?OutputKey==`AzureCgwId`].OutputValue' --output text 2>$null
    } else {
        $cgwId = aws cloudformation describe-stacks --stack-name "$prefix-10-customer-gateway" --region $region `
            --query 'Stacks[0].Outputs[?OutputKey==`GcpCgwId`].OutputValue' --output text 2>$null
    }
    if (-not $cgwId -or $cgwId -eq "None") { return "(CGW 미설정)" }
    $ip = aws ec2 describe-customer-gateways --customer-gateway-ids $cgwId --region $region `
        --query 'CustomerGateways[0].IpAddress' --output text 2>$null
    return $ip
}
