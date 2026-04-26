// modules/identity.bicep
// Function App 과 Logic Apps 가 Key Vault 에 암호 없이 접근하기 위한 관리 ID

param location string
param prefix string

// ── Function App 용 관리 ID ──────────────────────────────
resource functionIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-function'
  location: location
}

// ── Logic Apps 용 관리 ID ────────────────────────────────
resource logicappIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-logicapp'
  location: location
}

// ── 출력값 ───────────────────────────────────────────────
output functionIdentityId string = functionIdentity.id
output functionIdentityPrincipalId string = functionIdentity.properties.principalId
output functionIdentityClientId string = functionIdentity.properties.clientId

output logicappIdentityId string = logicappIdentity.id
output logicappIdentityPrincipalId string = logicappIdentity.properties.principalId
output logicappIdentityClientId string = logicappIdentity.properties.clientId
