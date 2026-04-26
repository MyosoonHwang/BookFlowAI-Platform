#!/bin/bash
# scripts/cleanup-all.sh
# 전체 배포 리소스 삭제 스크립트
# 대상: Resource Group 전체 + Entra ID 앱/그룹

set -e
export MSYS_NO_PATHCONV=1

RESOURCE_GROUP="rg-bookflow"
PREFIX="bookflow"

echo "========================================"
echo " BOOKFLOW Azure 전체 리소스 삭제"
echo "========================================"
echo ""
echo "삭제 대상:"
echo "  [Azure]"
echo "  - Resource Group : $RESOURCE_GROUP (하위 리소스 전체)"
echo "    ├── VPN Gateway      : vpngw-${PREFIX}"
echo "    ├── Public IP        : pip-${PREFIX}-vpngw-active/standby"
echo "    ├── Logic Apps       : la-${PREFIX}-notification, la-${PREFIX}-secret-rotation"
echo "    ├── Event Grid       : egt-${PREFIX}-keyvault"
echo "    ├── Function App     : func-${PREFIX}-sync"
echo "    ├── App Service Plan : asp-${PREFIX}"
echo "    ├── Storage Account  : stbookflowfunc"
echo "    ├── Key Vault        : kv-${PREFIX} (soft-delete 90일 유지)"
echo "    ├── Log Analytics    : law-${PREFIX}"
echo "    ├── VNet             : vnet-${PREFIX}"
echo "    ├── NSG              : nsg-${PREFIX}-services/function"
echo "    └── 관리 ID          : id-${PREFIX}-function/logicapp"
echo ""
echo "  [Entra ID] (entra-setup.sh 실행한 경우)"
echo "  - 앱 등록  : BookFlow-Internal"
echo "  - 그룹     : BF-HeadQuarter, BF-Logistics, BF-Branch, BF-Admin"
echo ""
echo "⚠️  Key Vault는 Purge Protection으로 인해 90일간 soft-delete 상태 유지"
echo "    같은 이름으로 재생성하려면 90일 후 가능"
echo ""
echo "계속하려면 Enter, 중단하려면 Ctrl+C"
read

# ── 0. 구독 확인 ───────────────────────────────────────────
echo ""
echo "[0] 현재 구독 확인"
az account show --output table
echo ""
echo "위 구독의 리소스를 삭제합니다. 정말 계속하려면 Enter, 중단하려면 Ctrl+C"
read

# ── 1. Resource Group 존재 확인 ───────────────────────────
echo ""
echo "[1] Resource Group 존재 확인"
RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP")
if [ "$RG_EXISTS" = "false" ]; then
  echo "  Resource Group '$RESOURCE_GROUP' 이 존재하지 않습니다."
else
  echo "  삭제 중: $RESOURCE_GROUP (5~15분 소요)"
  az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait
  echo "  삭제 요청 완료 — 백그라운드 진행 중"

  echo "  삭제 완료 대기 중..."
  az group wait \
    --name "$RESOURCE_GROUP" \
    --deleted \
    --timeout 900
  echo "  ✓ Resource Group 삭제 완료"
fi

# ── 2. Key Vault soft-delete 상태 확인 ────────────────────
echo ""
echo "[2] Key Vault soft-delete 상태 확인"
KV_DELETED=$(az keyvault list-deleted \
  --query "[?name=='kv-${PREFIX}'].name" \
  --output tsv 2>/dev/null || echo "")
if [ -n "$KV_DELETED" ]; then
  echo "  ℹ️  kv-${PREFIX}: soft-delete 상태 (90일 자동 만료)"
  echo "     deploy-all.sh 재실행 시 자동 복구됩니다 (purge protection으로 삭제 불가, recovery만 가능)"
else
  echo "  ✓ soft-delete 항목 없음"
fi

# ── 3. Entra ID 앱 삭제 ───────────────────────────────────
echo ""
echo "[3] Entra ID 앱 등록 삭제"
APP_ID=$(az ad app list \
  --display-name "BookFlow-Internal" \
  --query "[0].appId" --output tsv 2>/dev/null || echo "")
if [ -n "$APP_ID" ] && [ "$APP_ID" != "None" ]; then
  az ad app delete --id "$APP_ID"
  echo "  ✓ BookFlow-Internal 앱 삭제 완료"
else
  echo "  스킵: BookFlow-Internal 앱 없음"
fi

# ── 4. Entra ID 그룹 삭제 ─────────────────────────────────
echo ""
echo "[4] Entra ID 그룹 삭제"
for GROUP in "BF-HeadQuarter" "BF-Logistics" "BF-Branch" "BF-Admin"; do
  GROUP_ID=$(az ad group show \
    --group "$GROUP" \
    --query id --output tsv 2>/dev/null || echo "")
  if [ -n "$GROUP_ID" ]; then
    az ad group delete --group "$GROUP_ID"
    echo "  ✓ $GROUP 삭제 완료"
  else
    echo "  스킵: $GROUP 없음"
  fi
done

# ── 5. 최종 확인 ──────────────────────────────────────────
echo ""
echo "[5] 최종 확인"
RG_AFTER=$(az group exists --name "$RESOURCE_GROUP")
if [ "$RG_AFTER" = "false" ]; then
  echo "  ✓ Resource Group 삭제 확인"
else
  echo "  ✗ Resource Group 아직 존재 — Portal에서 수동 확인 필요"
fi

echo ""
echo "========================================"
echo " 전체 리소스 삭제 완료"
echo "========================================"
