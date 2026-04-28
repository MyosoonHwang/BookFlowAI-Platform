#!/bin/bash
# scripts/deploy-all.sh
# Day 1~3 통합 배포 스크립트 (스택별 구성, idempotent)
# 중단 후 재실행해도 완료된 스택은 자동 스킵됩니다.

set -e
export MSYS_NO_PATHCONV=1   # Git Bash 경로 자동변환 방지

RESOURCE_GROUP="rg-bookflow"
LOCATION="japanwest"
PREFIX="bookflow"

# ── 공통 함수 ─────────────────────────────────────────────

# 1. Bicep 문법 검사 (로컬, az bicep build)
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

# 2. Azure 배포 사전 검증 (az deployment group validate)
validate_deployment() {
  local deploy_name=$1
  shift
  echo "  [검증] Azure 배포 검증: $deploy_name"
  local result
  if ! result=$(az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
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

# ARM 배포가 이미 성공했는지 확인
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

# 스킵 또는 검증 후 배포 실행
deploy_stack() {
  local deploy_name=$1
  local template_file=""
  local args=("$@")

  # --template-file 값 추출 (검증에 사용)
  for i in "${!args[@]}"; do
    if [ "${args[$i]}" = "--template-file" ]; then
      template_file="${args[$((i+1))]}"
    fi
  done

  if check_deployed "$deploy_name"; then
    echo "  스킵: $deploy_name 이미 배포 완료"
    return 0
  fi

  # 문법 + Azure 검증
  [ -n "$template_file" ] && validate_bicep_syntax "$template_file" || return 1
  validate_deployment "$deploy_name" "${args[@]:1}" || return 1

  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$deploy_name" \
    --output table \
    "${args[@]:1}"
  echo "  완료: $deploy_name"
}

# ── 시작 ──────────────────────────────────────────────────
echo "========================================"
echo " BOOKFLOW Azure 통합 배포 (Day 1~3)"
echo "========================================"
echo ""
echo "[0] 현재 구독 확인"
az account show --output table
echo ""
echo "위 구독으로 진행합니다. 계속하려면 Enter, 중단하려면 Ctrl+C"
read

MY_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

# ════════════════════════════════════════════
# STACK 1: Foundation
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " [STACK 1] Foundation"
echo "════════════════════════════════════════"

# Resource Group
echo ""
echo "[1-1] Resource Group 생성/확인"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table

# Identity
echo ""
echo "[1-2] 관리 ID 배포"
deploy_stack "identity-deploy" \
  --template-file modules/identity.bicep \
  --parameters location="$LOCATION" prefix="$PREFIX"

FUNCTION_IDENTITY_ID=$(az identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "id-${PREFIX}-function" \
  --query id --output tsv)
FUNCTION_IDENTITY_PRINCIPAL=$(az identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "id-${PREFIX}-function" \
  --query principalId --output tsv)
FUNCTION_IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "id-${PREFIX}-function" \
  --query clientId --output tsv)
LOGICAPP_IDENTITY_ID=$(az identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "id-${PREFIX}-logicapp" \
  --query id --output tsv)
LOGICAPP_IDENTITY_PRINCIPAL=$(az identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "id-${PREFIX}-logicapp" \
  --query principalId --output tsv)
LOGICAPP_IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "id-${PREFIX}-logicapp" \
  --query clientId --output tsv)
echo "  Function Identity ID: $FUNCTION_IDENTITY_ID"
echo "  LogicApp Identity ID: $LOGICAPP_IDENTITY_ID"

# NSG
echo ""
echo "[1-3] NSG 배포"
deploy_stack "nsg-deploy" \
  --template-file modules/nsg.bicep \
  --parameters location="$LOCATION" prefix="$PREFIX"

SERVICES_NSG_ID=$(az network nsg show \
  --resource-group "$RESOURCE_GROUP" \
  --name "nsg-${PREFIX}-services" \
  --query id --output tsv)
FUNCTION_NSG_ID=$(az network nsg show \
  --resource-group "$RESOURCE_GROUP" \
  --name "nsg-${PREFIX}-function" \
  --query id --output tsv)

# Monitor
echo ""
echo "[1-4] Log Analytics Workspace 배포"
deploy_stack "monitor-deploy" \
  --template-file modules/monitor.bicep \
  --parameters location="$LOCATION" prefix="$PREFIX" logRetentionDays=90

LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "law-${PREFIX}" \
  --query id --output tsv)
echo "  Log Analytics ID: $LOG_ANALYTICS_ID"

# VNet
echo ""
echo "[1-5] VNet 배포"
deploy_stack "vnet-deploy" \
  --template-file modules/vnet.bicep \
  --parameters location="$LOCATION" \
              prefix="$PREFIX" \
              vnetAddressPrefix="172.16.0.0/16" \
              gatewaySubnetPrefix="172.16.1.0/27" \
              servicesSubnetPrefix="172.16.2.0/24" \
              functionSubnetPrefix="172.16.3.0/24" \
              servicesNsgId="$SERVICES_NSG_ID" \
              functionNsgId="$FUNCTION_NSG_ID"

GATEWAY_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "vnet-${PREFIX}" \
  --name GatewaySubnet \
  --query id --output tsv)
FUNCTION_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "vnet-${PREFIX}" \
  --name snet-function \
  --query id --output tsv)

# GatewaySubnet NSG 없음 검증
GATEWAY_NSG=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "vnet-${PREFIX}" \
  --name GatewaySubnet \
  --query networkSecurityGroup --output tsv 2>/dev/null || echo "")
if [ -z "$GATEWAY_NSG" ]; then
  echo "  ✓ GatewaySubnet NSG 없음 확인"
else
  echo "  ✗ 경고: GatewaySubnet 에 NSG 연결됨"
fi

# ════════════════════════════════════════════
# STACK 2: Security
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " [STACK 2] Security"
echo "════════════════════════════════════════"

echo ""
echo "[2-1] Key Vault 배포"
SECURITY_ADMIN_OBJECT_ID="$MY_OBJECT_ID"

# Soft-delete 상태인 Key Vault 복구 (purge protection 활성화로 삭제 불가)
KV_NAME="kv-${PREFIX}"
DELETED_KV=$(az keyvault list-deleted \
  --query "[?name=='${KV_NAME}'].name" \
  --output tsv 2>/dev/null || echo "")
if [ -n "$DELETED_KV" ]; then
  echo "  [복구] 소프트 삭제된 Key Vault 발견: $KV_NAME → 복구 중..."
  az keyvault recover --name "$KV_NAME" --location "$LOCATION"
  echo "  ✓ Key Vault 복구 완료"
fi

deploy_stack "keyvault-deploy" \
  --template-file modules/keyvault.bicep \
  --parameters location="$LOCATION" \
              prefix="$PREFIX" \
              logAnalyticsWorkspaceId="$LOG_ANALYTICS_ID" \
              functionIdentityPrincipalId="$FUNCTION_IDENTITY_PRINCIPAL" \
              logicappIdentityPrincipalId="$LOGICAPP_IDENTITY_PRINCIPAL" \
              securityAdminObjectId="$SECURITY_ADMIN_OBJECT_ID"

KV_URI=$(az keyvault show \
  --resource-group "$RESOURCE_GROUP" \
  --name "kv-${PREFIX}" \
  --query properties.vaultUri --output tsv)
KV_ID=$(az keyvault show \
  --resource-group "$RESOURCE_GROUP" \
  --name "kv-${PREFIX}" \
  --query id --output tsv)
echo "  Key Vault URI: $KV_URI"

# ════════════════════════════════════════════
# STACK 3: Compute
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " [STACK 3] Compute"
echo "════════════════════════════════════════"

echo ""
echo "[3-1] Function App 배포"
deploy_stack "function-deploy" \
  --template-file modules/function.bicep \
  --parameters location="$LOCATION" \
              prefix="$PREFIX" \
              keyVaultUri="$KV_URI" \
              functionIdentityId="$FUNCTION_IDENTITY_ID" \
              functionIdentityClientId="$FUNCTION_IDENTITY_CLIENT_ID" \
              logAnalyticsWorkspaceId="$LOG_ANALYTICS_ID"

FUNCTION_APP_ID=$(az functionapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "func-${PREFIX}-sync" \
  --query id --output tsv)

echo ""
echo "[3-2] Function 코드 배포"
if [ -d "functions/sync-secret" ]; then
  if check_deployed "function-deploy"; then
    # SCM(Kudu) 엔드포인트가 실제로 응답할 때까지 최대 4분 대기
    # app state=="Running"은 SCM 준비와 무관하므로 직접 HTTP 체크
    echo "  [대기] SCM 엔드포인트 준비 확인 중..."
    SCM_USER=$(az functionapp deployment list-publishing-credentials \
      --resource-group "$RESOURCE_GROUP" \
      --name "func-${PREFIX}-sync" \
      --query publishingUserName --output tsv 2>/dev/null)
    SCM_PASS=$(az functionapp deployment list-publishing-credentials \
      --resource-group "$RESOURCE_GROUP" \
      --name "func-${PREFIX}-sync" \
      --query publishingPassword --output tsv 2>/dev/null)

    for i in $(seq 1 24); do
      HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${SCM_USER}:${SCM_PASS}" \
        "https://func-${PREFIX}-sync.scm.azurewebsites.net/api/settings" 2>/dev/null)
      if [ "$HTTP" = "200" ]; then
        echo "  ✓ SCM 준비 완료 (${i}회, HTTP $HTTP)"
        break
      fi
      echo "  ... SCM 대기 중 (${i}회, HTTP: $HTTP)"
      sleep 10
    done

    cd functions/sync-secret
    # --build remote: Azure에서 빌드 → 로컬 Python 버전 불일치 문제 회피
    func azure functionapp publish "func-${PREFIX}-sync" --python --build remote
    cd ../..
    echo "  완료: Function 코드 배포"
  fi
else
  echo "  스킵: functions/sync-secret 폴더 없음"
fi

# ════════════════════════════════════════════
# STACK 4: Integration
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " [STACK 4] Integration"
echo "════════════════════════════════════════"

echo ""
echo "[4-1] Event Grid 배포"
deploy_stack "eventgrid-deploy" \
  --template-file modules/eventgrid.bicep \
  --parameters location="$LOCATION" \
              prefix="$PREFIX" \
              keyVaultId="$KV_ID"

# ════════════════════════════════════════════
# STACK 5: Automation
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " [STACK 5] Automation"
echo "════════════════════════════════════════"

echo ""
echo "[5-1] Logic Apps 배포"
deploy_stack "logicapp-deploy" \
  --template-file modules/logicapp.bicep \
  --parameters location="$LOCATION" \
              prefix="$PREFIX" \
              logicappIdentityId="$LOGICAPP_IDENTITY_ID" \
              logicappIdentityClientId="$LOGICAPP_IDENTITY_CLIENT_ID" \
              keyVaultUri="$KV_URI" \
              logAnalyticsWorkspaceId="$LOG_ANALYTICS_ID"

# ════════════════════════════════════════════
# STACK 6: Network (VPN Gateway, 30~45분)
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " [STACK 6] Network (VPN Gateway)"
echo "════════════════════════════════════════"
echo ""
echo "VPN Gateway 배포는 30~45분 소요됩니다."
echo "계속하려면 Enter, 건너뛰려면 Ctrl+C 후 나중에 재실행하세요"
read

echo ""
echo "[6-1] VPN Gateway 배포"
deploy_stack "vpn-deploy" \
  --template-file modules/vpn.bicep \
  --parameters location="$LOCATION" \
              prefix="$PREFIX" \
              gatewaySubnetId="$GATEWAY_SUBNET_ID" \
              vpnBgpAsn=65001

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

# ════════════════════════════════════════════
# 최종 검증
# ════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
echo " 최종 검증"
echo "════════════════════════════════════════"

echo ""
echo "[검증 1] 전체 리소스 목록"
az resource list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{type:type, name:name}" \
  --output table

echo ""
echo "[검증 2] Key Vault RBAC 확인"
az role assignment list --scope "$KV_ID" --output table

echo ""
echo "[검증 3] Logic Apps 상태"
az logic workflow list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{name:name, state:state}" \
  --output table

echo ""
echo "========================================"
echo " 전체 배포 완료"
echo "========================================"
echo ""
echo "수동으로 남은 작업:"
echo "  1. Azure Portal → la-${PREFIX}-notification: Teams·Outlook 커넥터 인증"
echo "  2. Azure Portal → la-${PREFIX}-secret-rotation: Outlook 커넥터 인증"
echo "  3. Entra ID 앱 등록: bash scripts/entra-setup.sh"
echo "  4. VPN 연결 시: bash scripts/vpn-connect.sh"
