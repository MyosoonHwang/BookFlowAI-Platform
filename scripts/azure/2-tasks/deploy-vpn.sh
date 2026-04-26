#!/bin/bash
# scripts/deploy-vpn.sh
# VPN Gateway 단독 배포 (30~45분 소요)
# deploy-all.sh 로 Stack 1~5 완료 후 실행

set -e
export MSYS_NO_PATHCONV=1

RESOURCE_GROUP="rg-bookflow"
LOCATION="japanwest"
PREFIX="bookflow"

validate_bicep_syntax() {
  local template=$1
  echo "  [검증] 문법 검사: $template"
  if ! az bicep build --file "$template" --outfile /dev/null 2>/tmp/bicep_err; then
    echo "  ✗ Bicep 문법 오류:"
    cat /tmp/bicep_err | sed 's/^/    /'
    return 1
  fi
  echo "  ✓ 문법 이상 없음"
}

validate_deployment() {
  local deploy_name=$1
  shift
  echo "  [검증] Azure 배포 검증: $deploy_name"
  local result
  if ! result=$(az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --name "$deploy_name" \
    --output json \
    "$@" 2>&1); then
    echo "  ✗ 배포 검증 실패:"
    echo "$result" | python3 -c "
import sys, json
try:
    err = json.load(sys.stdin)
    details = err.get('error', {}).get('details', [err.get('error', {})])
    for d in details:
        print('    -', d.get('message', d))
except:
    print(sys.stdin.read())
" 2>/dev/null || echo "$result" | sed 's/^/    /'
    return 1
  fi
  echo "  ✓ 배포 검증 통과"
}

check_deployed() {
  local name=$1
  local state
  state=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$name" \
    --query properties.provisioningState \
    --output tsv 2>/dev/null || echo "NotFound")
  [ "$state" = "Succeeded" ]
}

echo "========================================"
echo " BOOKFLOW VPN Gateway 배포"
echo "========================================"
echo ""
echo "[0] 현재 구독 확인"
az account show --output table
echo ""
echo "VPN Gateway 배포는 30~45분 소요됩니다."
echo "계속하려면 Enter, 중단하려면 Ctrl+C"
read

# GatewaySubnet ID 조회
echo ""
echo "[1] GatewaySubnet ID 조회"
GATEWAY_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "vnet-${PREFIX}" \
  --name GatewaySubnet \
  --query id --output tsv)
echo "  GatewaySubnet ID: $GATEWAY_SUBNET_ID"

# VPN Gateway 배포
echo ""
echo "[2] 기존 Public IP zones 충돌 확인 및 정리"
for PIP_NAME in "pip-${PREFIX}-vpngw-active" "pip-${PREFIX}-vpngw-standby"; do
  PIP_EXISTS=$(az network public-ip show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PIP_NAME" \
    --query name --output tsv 2>/dev/null || echo "")
  if [ -n "$PIP_EXISTS" ]; then
    PIP_ZONES=$(az network public-ip show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$PIP_NAME" \
      --query "zones" --output tsv 2>/dev/null || echo "")
    if [ -z "$PIP_ZONES" ]; then
      echo "  zones 없는 PIP 발견 → 삭제: $PIP_NAME"
      az network public-ip delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PIP_NAME"
      echo "  삭제 완료: $PIP_NAME"
    else
      echo "  ✓ $PIP_NAME zones 정상: $PIP_ZONES"
    fi
  fi
done

echo ""
echo "[3] VPN Gateway 배포 시작"
if check_deployed "vpn-deploy"; then
  echo "  스킵: vpn-deploy 이미 배포 완료"
else
  validate_bicep_syntax "modules/vpn.bicep" || exit 1
  validate_deployment "vpn-deploy" \
    --template-file modules/vpn.bicep \
    --parameters location="$LOCATION" \
                prefix="$PREFIX" \
                gatewaySubnetId="$GATEWAY_SUBNET_ID" \
                vpnBgpAsn=65001 || exit 1

  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "vpn-deploy" \
    --template-file modules/vpn.bicep \
    --parameters location="$LOCATION" \
                prefix="$PREFIX" \
                gatewaySubnetId="$GATEWAY_SUBNET_ID" \
                vpnBgpAsn=65001 \
    --output table
  echo "  완료: VPN Gateway 배포"
fi

# AWS 팀 전달값 출력
echo ""
echo "[4] AWS 팀 전달값 조회"
ACTIVE_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "pip-${PREFIX}-vpngw-active" \
  --query ipAddress --output tsv)
STANDBY_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "pip-${PREFIX}-vpngw-standby" \
  --query ipAddress --output tsv)
BGP_ASN=$(az network vnet-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "vpngw-${PREFIX}" \
  --query bgpSettings.asn --output tsv)
BGP_PEERING=$(az network vnet-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "vpngw-${PREFIX}" \
  --query bgpSettings.bgpPeeringAddress --output tsv)

echo ""
echo "========================================"
echo " AWS 팀에 전달할 값"
echo "========================================"
echo "  Active 공인 IP:  $ACTIVE_IP"
echo "  Standby 공인 IP: $STANDBY_IP"
echo "  BGP ASN:         $BGP_ASN"
echo "  BGP Peering IP:  $BGP_PEERING"
echo "========================================"
