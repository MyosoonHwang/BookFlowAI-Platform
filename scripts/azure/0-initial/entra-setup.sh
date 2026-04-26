#!/bin/bash
# scripts/entra-setup.sh
# Entra ID 앱 등록 및 Client Secret Key Vault 저장
# Bicep 으로 처리 불가한 부분 — CLI 로 진행

set -e

PREFIX="bookflow"
REDIRECT_URI="https://auth.bookflow.internal/callback"  # AWS 팀 확인 후 수정

echo "========================================"
echo " Entra ID 앱 등록 시작"
echo "========================================"

# ── 1. 앱 등록 ────────────────────────────────────────────
echo ""
echo "[1] 앱 등록"
APP_ID=$(az ad app create \
  --display-name "BookFlow-Internal" \
  --sign-in-audience AzureADMyOrg \
  --query appId --output tsv)
echo "앱 ID: $APP_ID"

# ── 2. 서비스 주체 생성 ───────────────────────────────────
echo ""
echo "[2] 서비스 주체 생성"
az ad sp create --id $APP_ID
echo "완료"

# ── 3. Redirect URI 설정 ──────────────────────────────────
echo ""
echo "[3] Redirect URI 설정: $REDIRECT_URI"
az ad app update \
  --id $APP_ID \
  --web-redirect-uris $REDIRECT_URI
echo "완료"

# ── 4. API 권한 추가 (openid, profile, email) ─────────────
echo ""
echo "[4] API 권한 추가"
az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 37f7f235-527c-4136-accd-4a02d197296e=Scope

az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 14dad69e-099b-42c9-810b-d002981feec1=Scope
echo "완료"

# ── 5. Client Secret 생성 ─────────────────────────────────
echo ""
echo "[5] Client Secret 생성"
CLIENT_SECRET=$(az ad app credential reset \
  --id $APP_ID \
  --years 1 \
  --query password --output tsv)
echo "Client Secret 생성 완료 (Key Vault 에 즉시 저장)"

TENANT_ID=$(az account show --query tenantId --output tsv)

# ── 6. Key Vault 에 저장 ──────────────────────────────────
echo ""
echo "[6] Key Vault 저장"
EXPIRES=$(date -u -d "+1 year" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+1y '+%Y-%m-%dT%H:%M:%SZ')

az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "bookflow-tenant-id" \
  --value "$TENANT_ID" \
  --expires "$EXPIRES"
echo "✓ tenant-id 저장"

az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "bookflow-client-id" \
  --value "$APP_ID" \
  --expires "$EXPIRES"
echo "✓ client-id 저장"

az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "bookflow-client-secret" \
  --value "$CLIENT_SECRET" \
  --expires "$EXPIRES"
echo "✓ client-secret 저장"

# VPN 연결 후 AWS 팀에게 받아서 채울 플레이스홀더
az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "aws-api-gateway-url" \
  --value "PLACEHOLDER-VPN-CONNECTED-LATER"
echo "✓ aws-api-gateway-url 플레이스홀더 저장"

# ── 7. 그룹 생성 ──────────────────────────────────────────
echo ""
echo "[7] Entra ID 그룹 생성"
az ad group create --display-name "BF-HeadQuarter" --mail-nickname "BF-HeadQuarter"
az ad group create --display-name "BF-Logistics" --mail-nickname "BF-Logistics"
az ad group create --display-name "BF-Branch" --mail-nickname "BF-Branch"
az ad group create --display-name "BF-Admin" --mail-nickname "BF-Admin"
echo "완료"

echo ""
echo "========================================"
echo " Entra ID 설정 완료"
echo "========================================"
echo ""
echo "AWS 팀에 전달할 값:"
echo "  테넌트 ID:    $TENANT_ID"
echo "  클라이언트 ID: $APP_ID"
echo ""
echo "주의: Client Secret 은 Key Vault 저장 완료"
echo "      VPN 연결 후 자동 동기화 흐름으로 AWS 에 전달 예정"
