#!/bin/bash
# scripts/entra-setup.sh
# Entra ID    Client Secret Key Vault 
# Bicep     — CLI  

set -e

PREFIX="bookflow"
REDIRECT_URI="https://auth.bookflow.internal/callback"  # AWS    

echo "========================================"
echo " Entra ID   "
echo "========================================"

# ── 1.   ────────────────────────────────────────────
echo ""
echo "[1]  "
APP_ID=$(az ad app create \
  --display-name "BookFlow-Internal" \
  --sign-in-audience AzureADMyOrg \
  --query appId --output tsv)
echo " ID: $APP_ID"

# ── 2.    ───────────────────────────────────
echo ""
echo "[2]   "
az ad sp create --id $APP_ID
echo ""

# ── 3. Redirect URI  ──────────────────────────────────
echo ""
echo "[3] Redirect URI : $REDIRECT_URI"
az ad app update \
  --id $APP_ID \
  --web-redirect-uris $REDIRECT_URI
echo ""

# ── 4. API   (openid, profile, email) ─────────────
echo ""
echo "[4] API  "
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
echo ""

# ── 5. Client Secret  ─────────────────────────────────
echo ""
echo "[5] Client Secret "
CLIENT_SECRET=$(az ad app credential reset \
  --id $APP_ID \
  --years 1 \
  --query password --output tsv)
echo "Client Secret   (Key Vault   )"

TENANT_ID=$(az account show --query tenantId --output tsv)

# ── 6. Key Vault   ──────────────────────────────────
echo ""
echo "[6] Key Vault "
EXPIRES=$(date -u -d "+1 year" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+1y '+%Y-%m-%dT%H:%M:%SZ')

az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "bookflow-tenant-id" \
  --value "$TENANT_ID" \
  --expires "$EXPIRES"
echo "✓ tenant-id "

az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "bookflow-client-id" \
  --value "$APP_ID" \
  --expires "$EXPIRES"
echo "✓ client-id "

az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "bookflow-client-secret" \
  --value "$CLIENT_SECRET" \
  --expires "$EXPIRES"
echo "✓ client-secret "

# VPN   AWS    
az keyvault secret set \
  --vault-name "kv-${PREFIX}" \
  --name "aws-api-gateway-url" \
  --value "PLACEHOLDER-VPN-CONNECTED-LATER"
echo "✓ aws-api-gateway-url  "

# ── 7.   ──────────────────────────────────────────
echo ""
echo "[7] Entra ID  "
az ad group create --display-name "BF-HeadQuarter" --mail-nickname "BF-HeadQuarter"
az ad group create --display-name "BF-Logistics" --mail-nickname "BF-Logistics"
az ad group create --display-name "BF-Branch" --mail-nickname "BF-Branch"
az ad group create --display-name "BF-Admin" --mail-nickname "BF-Admin"
echo ""

echo ""
echo "========================================"
echo " Entra ID  "
echo "========================================"
echo ""
echo "AWS   :"
echo "   ID:    $TENANT_ID"
echo "   ID: $APP_ID"
echo ""
echo ": Client Secret  Key Vault  "
echo "      VPN      AWS   "
