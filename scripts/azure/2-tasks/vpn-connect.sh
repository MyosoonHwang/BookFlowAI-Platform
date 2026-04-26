#!/bin/bash
# scripts/vpn-connect.sh
# AWS TGW 구축 완료 후 VPN Connection 생성
# 3일 구축 기간에는 실행하지 않음

set -e

RESOURCE_GROUP="rg-bookflow"
PREFIX="bookflow"

echo "========================================"
echo " VPN Connection 생성 (AWS TGW 연결)"
echo "========================================"
echo ""
echo "AWS 팀에게 받은 값을 입력하세요."
echo ""

read -p "AWS TGW Active 공인 IP: " AWS_TGW_ACTIVE_IP
read -p "AWS TGW BGP Peering IP: " AWS_TGW_BGP_IP
read -s -p "Pre-Shared Key (PSK): " PSK
echo ""

# VPN Connection 배포
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file modules/vpn-connection.bicep \
  --parameters \
    prefix=$PREFIX \
    vpnGatewayName="vpngw-${PREFIX}" \
    awsTgwActiveIp=$AWS_TGW_ACTIVE_IP \
    awsTgwBgpPeeringIp=$AWS_TGW_BGP_IP \
    preSharedKey=$PSK \
  --name "vpn-connection-deploy"

echo ""
echo "[검증] VPN Connection 상태 확인 (2~5분 소요)"
sleep 120
az network vpn-connection show \
  --resource-group $RESOURCE_GROUP \
  --name "conn-${PREFIX}-aws-active" \
  --query "{name:name, status:connectionStatus, egressBytes:egressBytesTransferred}" \
  --output table

echo ""
echo "[검증] BGP 경로 확인"
az network vnet-gateway list-learned-routes \
  --resource-group $RESOURCE_GROUP \
  --name "vpngw-${PREFIX}" \
  --output table

echo ""
echo "통신 확인을 위해 임시 VM 을 배치하려면 scripts/test-connectivity.sh 실행"
