#!/bin/bash
# scripts/cleanup-selective.sh
# 선택적 삭제 — 재배포 가능한 리소스만 제거
#
# 보존 (절대 삭제 안 함):
#   - Entra ID 앱/그룹  : BookFlow-Internal, BF-* 그룹
#   - Public IP 2개     : pip-bookflow-vpngw-active/standby
#
# 삭제 순서 (의존성 역순):
#   VPN Connection → Local NW GW → VPN Gateway
#   → Logic Apps → Event Grid → Function App → App Svc Plan → Storage
#   → Key Vault → Log Analytics → 테스트 VM → VNet → NSG → 관리 ID

set -e
export MSYS_NO_PATHCONV=1

RESOURCE_GROUP="rg-bookflow"
PREFIX="bookflow"

echo "========================================"
echo " BOOKFLOW 선택적 리소스 삭제"
echo "========================================"
echo ""
echo "보존:"
echo "  ✓ Entra ID 앱  : BookFlow-Internal"
echo "  ✓ Entra ID 그룹: BF-HeadQuarter / BF-Logistics / BF-Branch / BF-Admin"
echo "  ✓ Public IP    : pip-${PREFIX}-vpngw-active"
echo "  ✓ Public IP    : pip-${PREFIX}-vpngw-standby"
echo ""
echo "삭제 대상:"
echo "  VPN Connection, Local NW GW, VPN Gateway"
echo "  Logic Apps x2, Event Grid, Function App"
echo "  App Svc Plan, Storage Account"
echo "  Key Vault (soft-delete → 재배포 시 자동 복구)"
echo "  Log Analytics, VNet, NSG x2, 관리 ID x2"
echo ""
echo "계속하려면 Enter, 중단하려면 Ctrl+C"
read

echo ""
echo "[0] 구독 확인"
az account show --output table
echo ""
echo "계속하려면 Enter, 중단하려면 Ctrl+C"
read

# 리소스가 존재하는지 확인하는 헬퍼
_exists() { [ -n "$1" ] && [ "$1" != "None" ]; }

# ── 1. VPN Connection ─────────────────────────────────────
echo ""
echo "[1] VPN Connection 삭제"
VAL=$(az network vpn-connection show \
  --resource-group "$RESOURCE_GROUP" \
  --name "conn-${PREFIX}-aws-active" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az network vpn-connection delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "conn-${PREFIX}-aws-active"
  echo "  ✓ 삭제: conn-${PREFIX}-aws-active"
else
  echo "  스킵: conn-${PREFIX}-aws-active 없음"
fi

# ── 2. Local Network Gateway ──────────────────────────────
echo ""
echo "[2] Local Network Gateway 삭제"
VAL=$(az network local-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "lng-${PREFIX}-aws-active" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az network local-gateway delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "lng-${PREFIX}-aws-active"
  echo "  ✓ 삭제: lng-${PREFIX}-aws-active"
else
  echo "  스킵: lng-${PREFIX}-aws-active 없음"
fi

# ── 3. VPN Gateway (PIP 유지) ─────────────────────────────
echo ""
echo "[3] VPN Gateway 삭제 (PIP 보존)"
VAL=$(az network vnet-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "vpngw-${PREFIX}" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  echo "  삭제 중 (10~20분 소요)..."
  az network vnet-gateway delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "vpngw-${PREFIX}"
  echo "  ✓ 삭제: vpngw-${PREFIX}"
else
  echo "  스킵: vpngw-${PREFIX} 없음"
fi

echo ""
echo "  [PIP 보존 확인]"
for PIP in "pip-${PREFIX}-vpngw-active" "pip-${PREFIX}-vpngw-standby"; do
  IP=$(az network public-ip show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PIP" \
    --query ipAddress --output tsv 2>/dev/null || echo "없음")
  echo "  ✓ 보존: $PIP = $IP"
done

# ── 4. Logic Apps ─────────────────────────────────────────
echo ""
echo "[4] Logic Apps 삭제"
for LA in "la-${PREFIX}-notification" "la-${PREFIX}-secret-rotation"; do
  VAL=$(az logic workflow show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$LA" \
    --query name --output tsv 2>/dev/null || echo "")
  if _exists "$VAL"; then
    az logic workflow delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "$LA" \
      --yes
    echo "  ✓ 삭제: $LA"
  else
    echo "  스킵: $LA 없음"
  fi
done

# ── 5. Event Grid System Topic ────────────────────────────
echo ""
echo "[5] Event Grid 삭제"
VAL=$(az eventgrid system-topic show \
  --resource-group "$RESOURCE_GROUP" \
  --name "egt-${PREFIX}-keyvault" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az eventgrid system-topic delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "egt-${PREFIX}-keyvault" \
    --yes
  echo "  ✓ 삭제: egt-${PREFIX}-keyvault"
else
  echo "  스킵: egt-${PREFIX}-keyvault 없음"
fi

# ── 6. Function App ───────────────────────────────────────
echo ""
echo "[6] Function App 삭제"
VAL=$(az functionapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "func-${PREFIX}-sync" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az functionapp delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "func-${PREFIX}-sync"
  echo "  ✓ 삭제: func-${PREFIX}-sync"
else
  echo "  스킵: func-${PREFIX}-sync 없음"
fi

# ── 7. App Service Plan ───────────────────────────────────
echo ""
echo "[7] App Service Plan 삭제"
VAL=$(az appservice plan show \
  --resource-group "$RESOURCE_GROUP" \
  --name "asp-${PREFIX}" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az appservice plan delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "asp-${PREFIX}" \
    --yes
  echo "  ✓ 삭제: asp-${PREFIX}"
else
  echo "  스킵: asp-${PREFIX} 없음"
fi

# ── 8. Storage Account ────────────────────────────────────
echo ""
echo "[8] Storage Account 삭제"
ST_NAME="st${PREFIX//-/}func"
VAL=$(az storage account show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ST_NAME" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az storage account delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ST_NAME" \
    --yes
  echo "  ✓ 삭제: $ST_NAME"
else
  echo "  스킵: $ST_NAME 없음"
fi

# ── 9. Key Vault (soft-delete 전환) ───────────────────────
echo ""
echo "[9] Key Vault 삭제 (soft-delete — 시크릿 보존, 재배포 시 자동 복구)"
VAL=$(az keyvault show \
  --resource-group "$RESOURCE_GROUP" \
  --name "kv-${PREFIX}" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az keyvault delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "kv-${PREFIX}"
  echo "  ✓ soft-delete 전환: kv-${PREFIX} (90일 유지, 시크릿 보존)"
else
  echo "  스킵: kv-${PREFIX} 없음 (이미 soft-delete 상태일 수 있음)"
fi

# ── 10. Log Analytics ─────────────────────────────────────
echo ""
echo "[10] Log Analytics Workspace 삭제"
VAL=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "law-${PREFIX}" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az monitor log-analytics workspace delete \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "law-${PREFIX}" \
    --force \
    --yes
  echo "  ✓ 삭제: law-${PREFIX}"
else
  echo "  스킵: law-${PREFIX} 없음"
fi

# ── 11. 테스트 VM 삭제 (VNet 삭제 전 필수) ───────────────────
echo ""
echo "[11] 테스트 VM 삭제 (snet-services 서브넷 점유 해제)"
VM_NAME="vm-private-test"
VM_VAL=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VM_VAL"; then
  # VM 삭제 전 연결 리소스 ID 수집
  NIC_IDS=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "networkProfile.networkInterfaces[].id" \
    --output tsv 2>/dev/null || echo "")
  DISK_ID=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "storageProfile.osDisk.managedDisk.id" \
    --output tsv 2>/dev/null || echo "")
  PIP_IDS=""
  for NIC_ID in $NIC_IDS; do
    PIP_ID=$(az network nic show \
      --ids "$NIC_ID" \
      --query "ipConfigurations[].publicIpAddress.id" \
      --output tsv 2>/dev/null || echo "")
    if _exists "$PIP_ID"; then
      PIP_IDS="$PIP_IDS $PIP_ID"
    fi
  done

  az vm delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --yes
  echo "  ✓ 삭제: $VM_NAME"

  for NIC_ID in $NIC_IDS; do
    NIC_NAME=$(echo "$NIC_ID" | sed 's|.*/||')
    az network nic delete --ids "$NIC_ID" 2>/dev/null \
      && echo "  ✓ NIC 삭제: $NIC_NAME" || true
  done

  for PIP_ID in $PIP_IDS; do
    az network public-ip delete --ids "$PIP_ID" 2>/dev/null \
      && echo "  ✓ Public IP 삭제" || true
  done

  if _exists "$DISK_ID"; then
    az disk delete --ids "$DISK_ID" --yes 2>/dev/null \
      && echo "  ✓ OS Disk 삭제" || true
  fi
else
  echo "  스킵: $VM_NAME 없음"
fi

# ── 12. VNet ──────────────────────────────────────────────
echo ""
echo "[12] VNet 삭제"

# VNet 삭제 전 사전 정리: Bastion → 고아 NIC 순서로 제거
echo "  [사전 정리 1] Bastion Host 확인"
BASTION_NAME="vnet-${PREFIX}-bastion"
BASTION_VAL=$(az network bastion show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BASTION_NAME" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$BASTION_VAL"; then
  BASTION_PIP=$(az network bastion show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$BASTION_NAME" \
    --query "ipConfigurations[].publicIpAddress.id" \
    --output tsv 2>/dev/null || echo "")
  az network bastion delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$BASTION_NAME"
  echo "  ✓ Bastion 삭제: $BASTION_NAME"
  if _exists "$BASTION_PIP"; then
    az network public-ip delete --ids "$BASTION_PIP" 2>/dev/null \
      && echo "  ✓ Bastion Public IP 삭제" || true
  fi
else
  echo "  스킵: $BASTION_NAME 없음"
fi

echo "  [사전 정리 2] snet-services 서브넷 NIC 확인"
ORPHAN_NICS=$(az network nic list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?ipConfigurations[?contains(subnet.id, 'snet-services')]].id" \
  --output tsv 2>/dev/null || echo "")
for NIC_ID in $ORPHAN_NICS; do
  NIC_NAME=$(echo "$NIC_ID" | sed 's|.*/||')
  PIP_ID=$(az network nic show \
    --ids "$NIC_ID" \
    --query "ipConfigurations[].publicIpAddress.id" \
    --output tsv 2>/dev/null || echo "")
  az network nic delete --ids "$NIC_ID" 2>/dev/null \
    && echo "  ✓ NIC 삭제: $NIC_NAME" || true
  if _exists "$PIP_ID"; then
    az network public-ip delete --ids "$PIP_ID" 2>/dev/null \
      && echo "  ✓ Public IP 삭제" || true
  fi
done

VAL=$(az network vnet show \
  --resource-group "$RESOURCE_GROUP" \
  --name "vnet-${PREFIX}" \
  --query name --output tsv 2>/dev/null || echo "")
if _exists "$VAL"; then
  az network vnet delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "vnet-${PREFIX}"
  echo "  ✓ 삭제: vnet-${PREFIX}"
else
  echo "  스킵: vnet-${PREFIX} 없음"
fi

# ── 13. NSG ───────────────────────────────────────────────
echo ""
echo "[13] NSG 삭제"
for NSG in "nsg-${PREFIX}-services" "nsg-${PREFIX}-function"; do
  VAL=$(az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG" \
    --query name --output tsv 2>/dev/null || echo "")
  if _exists "$VAL"; then
    az network nsg delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "$NSG"
    echo "  ✓ 삭제: $NSG"
  else
    echo "  스킵: $NSG 없음"
  fi
done

# ── 14. 관리 ID ───────────────────────────────────────────
echo ""
echo "[14] 관리 ID 삭제"
for ID_NAME in "id-${PREFIX}-function" "id-${PREFIX}-logicapp"; do
  VAL=$(az identity show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ID_NAME" \
    --query name --output tsv 2>/dev/null || echo "")
  if _exists "$VAL"; then
    az identity delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "$ID_NAME"
    echo "  ✓ 삭제: $ID_NAME"
  else
    echo "  스킵: $ID_NAME 없음"
  fi
done

# ── 15. ARM 배포 이력 삭제 ───────────────────────────────
# deploy-all.sh의 check_deployed()는 이력 기반으로 스킵 여부를 판단함.
# 이력이 남아있으면 재배포 시 모든 스택이 "이미 완료"로 스킵되므로 반드시 제거.
echo ""
echo "[15] ARM 배포 이력 초기화"
for DEPLOY in identity-deploy nsg-deploy monitor-deploy vnet-deploy \
              keyvault-deploy function-deploy eventgrid-deploy \
              logicapp-deploy vpn-deploy; do
  STATE=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOY" \
    --query properties.provisioningState \
    --output tsv 2>/dev/null || echo "")
  if [ -n "$STATE" ]; then
    az deployment group delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "$DEPLOY" \
      --no-wait
    echo "  ✓ 이력 삭제: $DEPLOY"
  else
    echo "  스킵: $DEPLOY 이력 없음"
  fi
done

# ── 최종 확인 ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo " 최종 확인"
echo "════════════════════════════════════════"

echo ""
echo "[확인 1] 리소스 그룹 내 남은 리소스"
az resource list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{type:type, name:name}" \
  --output table

echo ""
echo "[확인 2] PIP 보존"
for PIP in "pip-${PREFIX}-vpngw-active" "pip-${PREFIX}-vpngw-standby"; do
  IP=$(az network public-ip show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PIP" \
    --query ipAddress --output tsv 2>/dev/null || echo "❌ 없음")
  echo "  $PIP = $IP"
done

echo ""
echo "[확인 3] Entra ID 앱 보존"
APP_ID=$(az ad app list \
  --display-name "BookFlow-Internal" \
  --query "[0].appId" --output tsv 2>/dev/null || echo "❌ 없음")
echo "  BookFlow-Internal App ID = $APP_ID"

echo ""
echo "========================================"
echo " 선택적 삭제 완료"
echo "========================================"
echo ""
echo "재배포 시:"
echo "  bash scripts/deploy-all.sh"
echo "    → Key Vault 자동 복구 (시크릿 보존)"
echo "  VPN 재연결 시:"
echo "    bash scripts/deploy-vpn.sh  (같은 PIP 재사용 → IP 변경 없음)"
