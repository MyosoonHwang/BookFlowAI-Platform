# BOOKFLOW · task-client-vpn · Client VPN Endpoint (3 담당자 access)
#   대상: 영헌·민지·우혁 (OpenVPN client 로 접속)
#   전제: base-up.ps1 + Tier 00 ACM cert 발급 (easy-rsa 수동 import 1회)
#   소요: ~5분
#   비용: ~$1.50/일 (Endpoint $0.15/h · Connection $0.05/h × 3 user)
#
#   접속 후:
#     - Internal ALB (BookFlow AI VPC) 직접 접근
#     - EKS Pod 디버그 (kubectl)
#     - RDS 접속 (psql)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-client-vpn · Client VPN Endpoint ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

if (-not (Test-Stack -Name "vpc-bookflow-ai" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}

# Route 53 Hosted Zone ID 조회 (선택 · CNAME 등록용)
$prefix = $env:BOOKFLOW_STACK_PREFIX
$hzId = aws cloudformation describe-stacks --stack-name "$prefix-10-route53" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`HostedZoneId`].OutputValue' --output text 2>$null

if ($hzId -and $hzId -ne "None") {
    Deploy-Stack -Tier "60" -Name "client-vpn" -Template "60-network-cross-cloud/client-vpn.yaml" `
        -Parameters @{ Route53HostedZoneId = $hzId }
} else {
    Deploy-Stack -Tier "60" -Name "client-vpn" -Template "60-network-cross-cloud/client-vpn.yaml"
}

Write-Step "═══ task-client-vpn 완료 ═══"
Write-Info  "OVPN 설정파일 다운로드:"
Write-Info  "  aws ec2 export-client-vpn-client-configuration ``"
Write-Info  '    --client-vpn-endpoint-id <id> --output text > bookflow-client.ovpn'
Write-Info  "Client cert · key 추가 후 OpenVPN client 에서 import"
