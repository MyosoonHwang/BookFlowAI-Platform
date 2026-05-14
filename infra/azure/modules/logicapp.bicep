// modules/logicapp.bicep
// Logic Apps Standard (WS1) — 4 workflows in one app
//   1. notification    — HTTP Trigger, 8종 알람 (inbound via VPN private endpoint)
//   2. daily-digest    — Recurrence 09:00 KST (outbound via VNet Integration)
//   3. plan-watcher    — Recurrence 매시간 (outbound via VNet Integration)
//   4. secret-rotation — Recurrence 02:00 KST
//
// Network:
//   Inbound : Private Endpoint (snet-bookflowmj-services) → VPN → EKS
//   Outbound: VNet Integration (snet-function) → VPN → AWS dashboard-svc
// DNS:
//   privatelink.azurewebsites.net → private endpoint IP
//   EKS CoreDNS에 Conditional Forwarder 설정 필요 (Person 1 담당)

param location string
param prefix string
param logicappIdentityId string
param logicappIdentityClientId string
param keyVaultUri string
param logAnalyticsWorkspaceId string

param acsEndpoint string
param acsSenderAddress string
param digestRecipients string
param dashboardBaseUrl string

// VNet 연동 서브넷
param functionSubnetId string   // outbound (delegation: Microsoft.Web/serverFarms 이미 설정됨)
param servicesSubnetId string   // inbound PE (privateEndpointNetworkPolicies: Disabled 이미 설정됨)
param vnetId string             // Private DNS Zone VNet 링크

// ── Storage Account (Logic Apps Standard 상태/워크플로우 파일 저장) ─
var storageAccountName = 'stla${replace(prefix, '-', '')}'

resource logicAppStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// ── App Service Plan (WorkflowStandard WS1) ────────────────
resource logicAppPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-la-${prefix}'
  location: location
  kind: 'elastic'
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  properties: {}
}

// ── Logic Apps Standard Site ───────────────────────────────
// 4개 워크플로우를 한 앱에서 호스팅
// 워크플로우 정의: infra/azure/workflows/{name}/workflow.json (zip deploy로 배포)
var storageConnStr = 'DefaultEndpointsProtocol=https;AccountName=${logicAppStorage.name};AccountKey=${logicAppStorage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'la-${prefix}'
  location: location
  kind: 'workflowapp,functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logicappIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: logicAppPlan.id
    siteConfig: {
      appSettings: [
        { name: 'APP_KIND',                                 value: 'workflowApp' }
        { name: 'FUNCTIONS_EXTENSION_VERSION',              value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME',                 value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION',             value: '~18' }
        { name: 'AzureWebJobsStorage',                      value: storageConnStr }
        { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: storageConnStr }
        { name: 'WEBSITE_CONTENTSHARE',                     value: 'la-${prefix}' }
        { name: 'WORKFLOWS_SUBSCRIPTION_ID',                value: subscription().subscriptionId }
        { name: 'WORKFLOWS_RESOURCE_GROUP_NAME',            value: resourceGroup().name }
        { name: 'WORKFLOWS_LOCATION_NAME',                  value: location }
        // ACS 발신 설정 (workflow.json에서 @appsetting('...') 으로 참조)
        { name: 'ACS_EMAIL_URI',                            value: 'https://${acsEndpoint}/emails:send?api-version=2023-03-31' }
        { name: 'ACS_SENDER',                               value: acsSenderAddress }
        { name: 'DIGEST_RECIPIENTS',                        value: digestRecipients }
        { name: 'DASHBOARD_URL',                            value: dashboardBaseUrl }
        { name: 'KEY_VAULT_URI',                            value: keyVaultUri }
        // Managed Identity (User-Assigned) 참조용
        { name: 'LA_IDENTITY_ID',                           value: logicappIdentityId }
        { name: 'LA_IDENTITY_CLIENT_ID',                    value: logicappIdentityClientId }
      ]
    }
    virtualNetworkSubnetId: functionSubnetId  // outbound VNet Integration → VPN → AWS
    vnetRouteAllEnabled: true
  }
}

// ── Private Endpoint (inbound) ─────────────────────────────
// snet-bookflowmj-services (172.16.2.0/24) 에 배치
// → EKS Pod는 VPN 터널을 통해 이 private IP로만 접근 가능
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-la-${prefix}'
  location: location
  properties: {
    subnet: { id: servicesSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-la-${prefix}'
        properties: {
          privateLinkServiceId: logicApp.id
          groupIds: ['sites']
        }
      }
    ]
  }
  dependsOn: [logicApp]
}

// ── Private DNS Zone ───────────────────────────────────────
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

// Azure VNet 에서 FQDN resolve
resource dnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-${prefix}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

// PE 생성 시 자동으로 A 레코드 등록 (la-${prefix} → private IP)
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: privateEndpoint
  name: 'dzg-la-${prefix}'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-la'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ── 진단 설정 ─────────────────────────────────────────────
resource diagLogicApp 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-${prefix}'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

// ── 출력값 ───────────────────────────────────────────────
output logicAppName string = logicApp.name
output logicAppFqdn string = logicApp.properties.defaultHostName
// ConfigMap에 사용할 base URL (FQDN 기반, private IP 아님)
// 실제 trigger sig는 배포 후 아래 명령으로 확인:
//   az logicapp workflow trigger show -g rg-bookflow -n la-${prefix} --workflow-name notification --trigger-name manual
output notificationBaseUrl string = 'https://${logicApp.properties.defaultHostName}'
output privateEndpointName string = privateEndpoint.name
