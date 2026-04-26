// modules/logicapp.bicep
// 발주 알림용 + Client Secret 자동 교체용 Logic Apps

param location string
param prefix string
param logicappIdentityId string
param logicappIdentityClientId string
param keyVaultUri string
param logAnalyticsWorkspaceId string

// ── 발주 알림용 Logic Apps ────────────────────────────────
resource logicAppNotification 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-${prefix}-notification'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logicappIdentityId}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        // AWS notification-svc 가 이 URL 을 HTTP POST 로 호출
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                message: { type: 'string' }
                isbn: { type: 'string' }
                qty: { type: 'number' }
                store_id: { type: 'string' }
                order_type: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        // Teams 알림 — 배포 후 Portal 에서 커넥터 수동 인증 필요
        Send_Teams_Message: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v3/beta/teams/@{encodeURIComponent(\'TEAMS_CHANNEL_ID\')}/channels/@{encodeURIComponent(\'TEAMS_TEAM_ID\')}/messages'
            body: {
              body: {
                content: '발주 알림: ISBN @{triggerBody()?[\'isbn\']} - 수량 @{triggerBody()?[\'qty\']} - @{triggerBody()?[\'message\']}'
                contentType: 'html'
              }
            }
          }
        }
        // Outlook 메일 — 배포 후 Portal 에서 커넥터 수동 인증 필요
        Send_Outlook_Email: {
          type: 'ApiConnection'
          runAfter: {
            Send_Teams_Message: ['Succeeded']
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/Mail'
            body: {
              To: 'publisher@example.com'
              Subject: '[BOOKFLOW] 발주 명세 - @{triggerBody()?[\'isbn\']}'
              Body: '발주 수량: @{triggerBody()?[\'qty\']}<br>메시지: @{triggerBody()?[\'message\']}'
              Importance: 'Normal'
            }
          }
        }
        Response: {
          type: 'Response'
          runAfter: {
            Send_Outlook_Email: ['Succeeded', 'Failed']
          }
          inputs: {
            statusCode: 200
            body: {
              result: 'ok'
            }
          }
        }
      }
    }
    parameters: {}
  }
}

// ── Client Secret 자동 교체용 Logic Apps ─────────────────
resource logicAppSecretRotation 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-${prefix}-secret-rotation'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logicappIdentityId}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        // 매일 새벽 02:00 실행
        Recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: ['2']
              minutes: [0]
            }
            timeZone: 'Korea Standard Time'
          }
        }
      }
      actions: {
        // Key Vault 시크릿 목록 조회
        List_Secrets: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '${keyVaultUri}secrets?api-version=7.4'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: logicappIdentityId
              audience: 'https://vault.azure.net'
            }
          }
        }
        // 만료 30일 이하 시크릿 필터링 후 교체 워크플로우 실행
        // 상세 교체 로직은 배포 후 Portal 에서 추가 구성
        Notify_Admin: {
          type: 'ApiConnection'
          runAfter: {
            List_Secrets: ['Succeeded']
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/Mail'
            body: {
              To: 'admin@example.com'
              Subject: '[BOOKFLOW] Secret 교체 점검 실행'
              Body: 'Secret 만료 점검이 실행됐습니다.'
              Importance: 'Normal'
            }
          }
        }
      }
    }
    parameters: {}
  }
}

// ── 진단 설정 ─────────────────────────────────────────────
resource notificationDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-notification'
  scope: logicAppNotification
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

resource rotationDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-rotation'
  scope: logicAppSecretRotation
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// ── 출력값 ───────────────────────────────────────────────
output notificationLogicAppId string = logicAppNotification.id
output notificationLogicAppName string = logicAppNotification.name
output rotationLogicAppId string = logicAppSecretRotation.id
output rotationLogicAppName string = logicAppSecretRotation.name
