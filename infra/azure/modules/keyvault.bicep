// modules/keyvault.bicep

param location string
param prefix string
param logAnalyticsWorkspaceId string
param functionIdentityPrincipalId string
param logicappIdentityPrincipalId string
param securityAdminObjectId string

var keyVaultAdministratorRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${prefix}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Security Administrator → Key Vault Administrator
resource roleAssignAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, securityAdminObjectId, keyVaultAdministratorRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleId)
    principalId: securityAdminObjectId
    principalType: 'User'
  }
}

// Function App 관리 ID → Key Vault Secrets User
resource roleAssignFunction 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionIdentityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: functionIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Logic Apps 관리 ID → Key Vault Secrets User
resource roleAssignLogicApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logicappIdentityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: logicappIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 진단 설정
resource kvDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${prefix}-kv'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
