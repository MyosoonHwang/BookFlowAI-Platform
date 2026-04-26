// modules/eventgrid.bicep
// Key Vault 이벤트 소스 시스템 토픽
// 구독(Subscription)은 함수 코드 배포 후 Portal에서 수동 연결

param location string
param prefix string
param keyVaultId string

resource eventGridTopic 'Microsoft.EventGrid/systemTopics@2023-06-01-preview' = {
  name: 'egt-${prefix}-keyvault'
  location: location
  properties: {
    source: keyVaultId
    topicType: 'Microsoft.KeyVault.vaults'
  }
}

output eventGridTopicId string = eventGridTopic.id
output eventGridTopicName string = eventGridTopic.name
