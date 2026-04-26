#!/bin/bash
# scripts/test-connectivity.sh
# VPN 연결 후 통신 검증용 임시 VM 배치 및 테스트
# 검증 완료 후 VM 즉시 삭제

set -e

RESOURCE_GROUP="rg-bookflow"
PREFIX="bookflow"
TEST_VM_NAME="vm-test-connectivity"

echo "========================================"
echo " 통신 검증용 임시 VM 배치"
echo "========================================"

read -p "AWS EC2 프라이빗 IP (ping 테스트 대상): " AWS_EC2_IP

# ── 임시 VM 생성 ─────────────────────────────────────────
echo ""
echo "[1] 임시 VM 생성 (snet-services 서브넷)"
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $TEST_VM_NAME \
  --image Ubuntu2204 \
  --vnet-name "vnet-${PREFIX}" \
  --subnet snet-services \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --output table

# 공인 IP 조회
VM_PUBLIC_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name $TEST_VM_NAME \
  --show-details \
  --query publicIps --output tsv)

echo "VM 공인 IP: $VM_PUBLIC_IP"

# ── 통신 테스트 ───────────────────────────────────────────
echo ""
echo "[2] AWS EC2 ping 테스트"
echo "SSH 로 VM 접속 후 직접 확인:"
echo "  ssh azureuser@$VM_PUBLIC_IP"
echo "  ping -c 4 $AWS_EC2_IP"
echo ""
echo "자동 ping 테스트 실행 중..."
ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    azureuser@$VM_PUBLIC_IP \
    "ping -c 4 $AWS_EC2_IP" || echo "ping 실패 — Security Group/NSG 또는 VPN 라우팅 확인 필요"

# ── 임시 VM 삭제 ─────────────────────────────────────────
echo ""
echo "[3] 임시 VM 삭제"
read -p "검증 완료 후 VM 삭제하려면 Enter"
az vm delete \
  --resource-group $RESOURCE_GROUP \
  --name $TEST_VM_NAME \
  --yes

# VM 관련 리소스 정리 (NIC, 공인 IP, 디스크)
az network nic delete \
  --resource-group $RESOURCE_GROUP \
  --name "${TEST_VM_NAME}VMNic" 2>/dev/null || true
az network public-ip delete \
  --resource-group $RESOURCE_GROUP \
  --name "${TEST_VM_NAME}PublicIP" 2>/dev/null || true

echo "임시 VM 및 관련 리소스 삭제 완료"
