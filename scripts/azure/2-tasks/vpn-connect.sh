#!/bin/bash
# scripts/vpn-connect.sh
# AWS CloudFormation YAML 자동 파싱 → Azure Local Network Gateway + VPN Connection 생성
#
# 의존성:
#   1. scripts/deploy-vpn.sh 완료 (Azure VPN Gateway 배포)
#   2. AWS 측 vpn-site-to-site.yaml 스택 배포 완료
#      (EnableAzureVpn=true · Azure VPN GW IP 주입 상태)
#
# 파싱 소스:
#   infra/aws/60-network-cross-cloud/tgw.yaml            → AWS_ASN
#   infra/aws/60-network-cross-cloud/vpn-site-to-site.yaml → Tunnel Inside CIDR
#   infra/aws/10-network-core/vpc-*.yaml                 → VPC CIDR
#   AWS CLI (bookflow-60-vpn-site-to-site 스택)          → Gateway IP, PSK

set -e
export MSYS_NO_PATHCONV=1

RESOURCE_GROUP="rg-bookflow"
PREFIX="bookflow"
REGION="${AWS_REGION:-ap-northeast-1}"
AWS_STACK_PREFIX="bookflow"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INFRA_AWS="${REPO_ROOT}/infra/aws"

echo "========================================"
echo " BOOKFLOW VPN Connection 생성"
echo " (AWS TGW ↔ Azure VPN Gateway · BGP)"
echo "========================================"
echo ""

# ── 0. 전제조건 확인 ───────────────────────────────────────
echo "[0] 전제조건 확인"

if ! command -v aws &>/dev/null; then
  echo "  ✗ AWS CLI 미설치 — 설치 후 재실행"
  exit 1
fi
if ! az account show --output none 2>/dev/null; then
  echo "  ✗ Azure CLI 미인증 — 'az login' 후 재실행"
  exit 1
fi
VPN_GW=$(az network vnet-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "vpngw-${PREFIX}" \
  --query name --output tsv 2>/dev/null || echo "")
if [ -z "$VPN_GW" ]; then
  echo "  ✗ Azure VPN Gateway 'vpngw-${PREFIX}' 없음 — deploy-vpn.sh 먼저 실행"
  exit 1
fi
echo "  ✓ AWS CLI / Azure CLI / VPN Gateway 확인 완료"
echo ""

# ── 1. CloudFormation YAML 파싱 (정적 값) ─────────────────
echo "[1] CloudFormation YAML 파싱"

TGW_YAML="${INFRA_AWS}/60-network-cross-cloud/tgw.yaml"
VPN_YAML="${INFRA_AWS}/60-network-cross-cloud/vpn-site-to-site.yaml"

# AWS_ASN: tgw.yaml → TgwAsn.Default
AWS_ASN=$(grep -A3 'TgwAsn:' "$TGW_YAML" | grep 'Default:' | grep -oE '[0-9]+' | head -1)
if [ -z "$AWS_ASN" ]; then
  echo "  ✗ AWS_ASN 파싱 실패 — $TGW_YAML 확인 필요"
  exit 1
fi
echo "  AWS_ASN (TGW BGP): $AWS_ASN"

# Azure 터널 Inside CIDR → AWS BGP Peer IP (CIDR 네트워크+1)
# vpn-site-to-site.yaml: AzureVpnConnection Tunnel1 = 169.254.21.4/30 → AWS=169.254.21.5
TUNNEL1_CIDR=$(grep -A20 'AzureVpnConnection:' "$VPN_YAML" \
  | grep 'TunnelInsideCidr:' | head -1 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+')
if [ -z "$TUNNEL1_CIDR" ]; then
  echo "  ✗ Tunnel Inside CIDR 파싱 실패 — $VPN_YAML 확인 필요"
  exit 1
fi
TUNNEL_NET=$(echo "$TUNNEL1_CIDR" | cut -d'/' -f1)
IFS='.' read -r _o1 _o2 _o3 _o4 <<< "$TUNNEL_NET"
AWS_BGP_PEER_IP="${_o1}.${_o2}.${_o3}.$((_o4 + 1))"
echo "  Tunnel1 Inside CIDR : $TUNNEL1_CIDR"
echo "  AWS BGP Peer IP     : $AWS_BGP_PEER_IP  (Azure가 BGP 피어링할 AWS 측 IP)"

# VPC CIDRs (TGW 연결된 4개 VPC)
VPC_FILES=(
  "${INFRA_AWS}/10-network-core/vpc-bookflow-ai.yaml"
  "${INFRA_AWS}/10-network-core/vpc-sales-data.yaml"
  "${INFRA_AWS}/10-network-core/vpc-egress.yaml"
  "${INFRA_AWS}/10-network-core/vpc-data.yaml"
)
AWS_VPC_CIDRS=()
for _f in "${VPC_FILES[@]}"; do
  _cidr=$(grep -m1 'CidrBlock:' "$_f" | grep -oE '10\.[0-9]+\.0\.0/16' || echo "")
  [ -n "$_cidr" ] && AWS_VPC_CIDRS+=("$_cidr")
done
if [ ${#AWS_VPC_CIDRS[@]} -eq 0 ]; then
  echo "  ✗ VPC CIDR 파싱 실패"
  exit 1
fi
echo "  AWS VPC CIDRs       : ${AWS_VPC_CIDRS[*]}"

# ── 2. AWS CLI로 런타임 값 조회 ────────────────────────────
echo ""
echo "[2] AWS CLI로 VPN Connection 정보 조회"
echo "  스택: ${AWS_STACK_PREFIX}-60-vpn-site-to-site (리전: $REGION)"

VPN_CONN_ID=$(aws cloudformation describe-stacks \
  --stack-name "${AWS_STACK_PREFIX}-60-vpn-site-to-site" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AzureVpnConnectionId'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [ -z "$VPN_CONN_ID" ] || [ "$VPN_CONN_ID" = "None" ]; then
  echo ""
  echo "  ⚠️  AWS VPN Connection 자동 조회 실패"
  echo "     원인: AWS CLI 미인증 또는 스택 미배포"
  echo "     AWS 콘솔 → EC2 → Site-to-Site VPN → bookflow-vpn-azure"
  echo "     에서 Tunnel 1 Outside IP 와 PSK 를 직접 확인하세요."
  echo ""
  read -p "  AWS TGW Outside IP (Tunnel1): " AWS_GATEWAY_IP
  read -s -p "  Pre-Shared Key (PSK)        : " PSK
  echo ""
else
  echo "  VPN Connection ID: $VPN_CONN_ID"

  # Tunnel1 Outside IP
  AWS_GATEWAY_IP=$(aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$VPN_CONN_ID" \
    --region "$REGION" \
    --query "VpnConnections[0].VgwTelemetry[0].OutsideIpAddress" \
    --output text 2>/dev/null || echo "")

  # PSK: CustomerGatewayConfiguration XML → <pre_shared_key> 첫 번째 항목
  CONFIG_XML=$(aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$VPN_CONN_ID" \
    --region "$REGION" \
    --query "VpnConnections[0].CustomerGatewayConfiguration" \
    --output text 2>/dev/null || echo "")
  PSK=$(echo "$CONFIG_XML" \
    | sed -n 's/.*<pre_shared_key>\([^<]*\)<\/pre_shared_key>.*/\1/p' \
    | head -1)

  if [ -z "$AWS_GATEWAY_IP" ] || [ "$AWS_GATEWAY_IP" = "None" ]; then
    echo "  ⚠️  TGW Outside IP 자동 조회 실패 (VPN Connection 아직 활성화 전일 수 있음)"
    read -p "  AWS TGW Outside IP (Tunnel1, 수동 입력): " AWS_GATEWAY_IP
  fi
  if [ -z "$PSK" ]; then
    echo "  ⚠️  PSK 자동 추출 실패"
    read -s -p "  Pre-Shared Key (PSK, 수동 입력): " PSK
    echo ""
  fi
fi

echo "  AWS_GATEWAY_IP: $AWS_GATEWAY_IP"
echo "  PSK           : ****"
echo ""

# ── 확인 후 진행 ──────────────────────────────────────────
echo "파싱 결과:"
echo "  AWS_ASN         : $AWS_ASN"
echo "  AWS_BGP_PEER_IP : $AWS_BGP_PEER_IP"
echo "  AWS_GATEWAY_IP  : $AWS_GATEWAY_IP"
echo "  VPC CIDRs       : ${AWS_VPC_CIDRS[*]}"
echo ""
echo "위 값으로 Azure VPN 연결을 생성합니다. 계속하려면 Enter, 중단하려면 Ctrl+C"
read

# ── 3. Azure Local Network Gateway 생성/갱신 ──────────────
echo ""
echo "[3] Azure Local Network Gateway 생성 (BGP 설정 포함)"
LNG_EXISTS=$(az network local-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "lng-${PREFIX}-aws-active" \
  --query name --output tsv 2>/dev/null || echo "")

if [ -n "$LNG_EXISTS" ]; then
  echo "  기존 LNG 발견 — 삭제 후 재생성 (BGP 설정 변경에는 재생성 필요)"
  az network local-gateway delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "lng-${PREFIX}-aws-active"
  echo "  ✓ 기존 LNG 삭제 완료"
fi

az network local-gateway create \
  --resource-group "$RESOURCE_GROUP" \
  --name "lng-${PREFIX}-aws-active" \
  --gateway-ip-address "$AWS_GATEWAY_IP" \
  --local-address-prefixes "${AWS_VPC_CIDRS[@]}" \
  --asn "$AWS_ASN" \
  --bgp-peering-address "$AWS_BGP_PEER_IP" \
  --output table
echo "  ✓ Local Network Gateway 생성 완료"
echo "    --asn              : $AWS_ASN"
echo "    --bgp-peering-address: $AWS_BGP_PEER_IP"
echo "    --gateway-ip-address : $AWS_GATEWAY_IP"

# ── 4. Azure VPN Connection 생성 ──────────────────────────
echo ""
echo "[4] Azure VPN Connection 생성 (BGP 활성)"
CONN_EXISTS=$(az network vpn-connection show \
  --resource-group "$RESOURCE_GROUP" \
  --name "conn-${PREFIX}-aws-active" \
  --query name --output tsv 2>/dev/null || echo "")

if [ -n "$CONN_EXISTS" ]; then
  echo "  기존 Connection 발견 — 삭제 후 재생성"
  az network vpn-connection delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "conn-${PREFIX}-aws-active"
  echo "  ✓ 기존 Connection 삭제 완료"
fi

az network vpn-connection create \
  --resource-group "$RESOURCE_GROUP" \
  --name "conn-${PREFIX}-aws-active" \
  --vnet-gateway1 "vpngw-${PREFIX}" \
  --local-gateway2 "lng-${PREFIX}-aws-active" \
  --shared-key "$PSK" \
  --enable-bgp \
  --output table
echo "  ✓ VPN Connection 생성 완료 (BGP 활성)"

# ── 5. 연결 상태 검증 ─────────────────────────────────────
echo ""
echo "[5] 연결 상태 확인 (BGP negotiation 2~5분 소요)"
echo "  2분 대기 중..."
sleep 120

az network vpn-connection show \
  --resource-group "$RESOURCE_GROUP" \
  --name "conn-${PREFIX}-aws-active" \
  --query "{name:name, status:connectionStatus, bgpEnabled:enableBgp, egress:egressBytesTransferred}" \
  --output table

echo ""
echo "[6] BGP 학습 경로 확인"
az network vnet-gateway list-learned-routes \
  --resource-group "$RESOURCE_GROUP" \
  --name "vpngw-${PREFIX}" \
  --output table

echo ""
echo "========================================"
echo " VPN Connection 생성 완료"
echo "========================================"
echo "  Local NW GW   : lng-${PREFIX}-aws-active"
echo "  VPN Connection: conn-${PREFIX}-aws-active"
echo "  BGP ASN (AWS) : $AWS_ASN"
echo "  BGP Peer IP   : $AWS_BGP_PEER_IP"
echo "  AWS VPC CIDRs : ${AWS_VPC_CIDRS[*]}"
echo ""
echo "통신 확인: bash scripts/test-connectivity.sh"
