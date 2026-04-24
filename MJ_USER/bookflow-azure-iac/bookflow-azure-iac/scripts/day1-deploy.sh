#!/bin/bash
# scripts/day1-deploy.sh
# 1일차: Resource Group, NSG, VNet, Key Vault, Monitor

set -e

RESOURCE_GROUP="rg-bookflow"
LOCATION="koreacentral"
PREFIX="bookflow"

echo "========================================"
echo " BOOKFLOW Azure 1일차 구축 시작"
echo "========================================"

# ── 0. 사전 확인 ─────────────────────────────────────────
echo ""
echo "[0] 사전 확인"
az account show --output table
echo ""
echo "위 구독으로 진행합니다. 계속하려면 Enter, 중단하려면 Ctrl+C"
read

# 현재 사용자 Object ID 조회
MY_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
echo "현재 사용자 Object ID: $MY_OBJECT_ID"
echo "parameters/dev.json 의 deploymentPrincipalObjectId 를 이 값으로 업데이트하세요."
echo ""

# ── 1. Resource Group 생성 ────────────────────────────────
echo "[1] Resource Group 생성"
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
echo "완료: Resource Group 생성"

# ── 2. 관리 ID 배포 ───────────────────────────────────────
echo ""
echo "[2] 관리 ID 배포"
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file modules/identity.bicep \
  --parameters location=koreacentral prefix=bookflow \
  --name "identity-deploy" \
  --output table
echo "완료: 관리 ID 배포"

# 관리 ID Principal ID 조회 (Key Vault RBAC 설정에 필요)
FUNCTION_IDENTITY_PRINCIPAL=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name "id-${PREFIX}-function" \
  --query principalId --output tsv)
LOGICAPP_IDENTITY_PRINCIPAL=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name "id-${PREFIX}-logicapp" \
  --query principalId --output tsv)
echo "Function 관리 ID Principal ID: $FUNCTION_IDENTITY_PRINCIPAL"
echo "LogicApp 관리 ID Principal ID: $LOGICAPP_IDENTITY_PRINCIPAL"

# ── 3. NSG 배포 ───────────────────────────────────────────
echo ""
echo "[3] NSG 배포"
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file modules/nsg.bicep \
  --parameters location=koreacentral prefix=bookflow \
  --name "nsg-deploy" \
  --output table
echo "완료: NSG 배포"

# NSG 검증
echo ""
echo "[검증] NSG 목록 확인"
az network nsg list \
  --resource-group $RESOURCE_GROUP \
  --output table

# ── 4. VNet 배포 ──────────────────────────────────────────
echo ""
echo "[4] VNet 배포"
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file modules/vnet.bicep \
  --parameters parameters/dev.json \
  --name "vnet-deploy" \
  --output table
echo "완료: VNet 배포"

# VNet 검증
echo ""
echo "[검증] 서브넷 목록 확인"
az network vnet subnet list \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "vnet-${PREFIX}" \
  --output table

# GatewaySubnet 에 NSG 없는지 확인
GATEWAY_NSG=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "vnet-${PREFIX}" \
  --name GatewaySubnet \
  --query networkSecurityGroup --output tsv)
if [ -z "$GATEWAY_NSG" ]; then
  echo "✓ GatewaySubnet NSG 없음 확인"
else
  echo "✗ 경고: GatewaySubnet 에 NSG 가 연결됨 — 제거 필요"
fi

# ── 5. Monitor 배포 ───────────────────────────────────────
echo ""
echo "[5] Log Analytics Workspace 배포"
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file modules/monitor.bicep \
  --parameters parameters/dev.json \
  --name "monitor-deploy" \
  --output table
echo "완료: Monitor 배포"

# ── 6. Key Vault 배포 ─────────────────────────────────────
echo ""
echo "[6] Key Vault 배포"
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file modules/keyvault.bicep \
  --parameters parameters/dev.json \
  --name "keyvault-deploy" \
  --output table
echo "완료: Key Vault 배포"

# Key Vault 검증
echo ""
echo "[검증] Key Vault 접근 테스트"
az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "test-secret" \
  --value "test-value-day1"
echo "✓ 시크릿 생성 성공"

SECRET_VAL=$(az keyvault secret show \
  --vault-name "kv-${PREFIX}" \
  --name "test-secret" \
  --query value --output tsv)
echo "✓ 시크릿 조회 성공: $SECRET_VAL"

az keyvault secret delete \
  --vault-name "kv-${PREFIX}" \
  --name "test-secret"
echo "✓ 테스트 시크릿 삭제 완료"

echo ""
echo "========================================"
echo " 1일차 구축 완료"
echo "========================================"
echo ""
echo "다음 단계 (2일차) 진행 전 확인사항:"
echo "1. parameters/dev.json 의 securityAdminObjectId 입력"
echo "2. parameters/dev.json 의 deploymentPrincipalObjectId 에 $MY_OBJECT_ID 입력"
echo "3. Entra ID 앱 등록은 scripts/entra-setup.sh 실행"
