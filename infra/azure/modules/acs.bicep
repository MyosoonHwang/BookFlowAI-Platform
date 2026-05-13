// modules/acs.bicep
// Azure Communication Services Email
//   - ACS Email Service (global · dataLocation=Japan)
//   - AzureManagedDomain  → 무료 발신 도메인 (DoNotReply@xxx.azurecomm.net)
//   - Communication Service (linked domain)
//   - RBAC: Logic App MI → Contributor on ACS (Managed Identity HTTP auth 용)

param prefix string
param logicappIdentityPrincipalId string

resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: 'acs-email-${prefix}'
  location: 'global'
  properties: {
    dataLocation: 'Japan'
  }
}

resource domain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  properties: {
    domainManagement: 'AzureManaged'
  }
}

resource commService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: 'acs-${prefix}'
  location: 'global'
  properties: {
    dataLocation: 'Japan'
    linkedDomains: [domain.id]
  }
}

// Logic App MI → Contributor on ACS (data plane email send 허용)
resource logicAppAcsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: commService
  name: guid(commService.id, logicappIdentityPrincipalId, 'acs-contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: logicappIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// commService.properties.hostName = "acs-bookflowmj.communication.azure.com"
output acsEndpoint string = commService.properties.hostName
// DoNotReply@{mailFromSenderDomain} 형식
output acsSenderAddress string = 'DoNotReply@${domain.properties.mailFromSenderDomain}'
output acsResourceId string = commService.id
