// modules/monitor.bicep
// Log Analytics Workspace 와 진단 설정

param location string
param prefix string
param logRetentionDays int

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-${prefix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── 출력값 ───────────────────────────────────────────────
output workspaceId string = logAnalytics.id
output workspaceName string = logAnalytics.name
