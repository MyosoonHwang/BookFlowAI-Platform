// modules/logicapp.bicep
// Logic Apps 4종:
//   1. la-notification    — HTTP Trigger, 8종 알람 (ACS Email · recipients payload 기반)
//   2. la-daily-digest    — Recurrence 09:00 KST, 일일 요약 메일 (ACS Email · digestRecipients param)
//   3. la-plan-watcher    — Recurrence 매시간, PENDING=0 감지 → ACS Email
//   4. la-secret-rotation — Recurrence 02:00 KST, Key Vault 시크릿 만료 점검 → ACS Email
//
// 이메일 발송: Outlook.com 커넥터 제거 → ACS Email REST API (Logic App MI 인증)
// 수신자:
//   - la-notification:    triggerBody()['recipients'] (notification-svc 가 동적 결정)
//   - la-daily-digest:    digestRecipients 파라미터 (JSON 배열 문자열, 본사+경영진+WH+지점 전체)
//   - la-plan-watcher:    digestRecipients 파라미터 (동일)
//   - la-secret-rotation: digestRecipients 파라미터 (동일)

param location string
param prefix string
param logicappIdentityId string
param logicappIdentityClientId string
param keyVaultUri string
param logAnalyticsWorkspaceId string

// ACS 발신 설정
param acsEndpoint string      // e.g. acs-bookflowmj.communication.azure.com
param acsSenderAddress string // e.g. DoNotReply@xxx.azurecomm.net

// 수신자 JSON 배열 (문자열 직렬화 · Logic App 내에서 json() 파싱)
// 형식: '[{"address":"a@b.com","displayName":"이름"},...]'
param digestRecipients string   // 일일 요약·계획 완료: 본사+경영진+WH+지점 전체

param dashboardBaseUrl string

// ── ACS Email 공통 변수 ─────────────────────────────────────
var acsEmailUri = 'https://${acsEndpoint}/emails:send?api-version=2023-03-31'
var acsAuth = {
  type: 'ManagedServiceIdentity'
  identity: logicappIdentityId
  audience: 'https://communication.azure.com'
}

// ═══════════════════════════════════════════════════════════
// 1. 알림 Logic App — HTTP Trigger, 8종 event_type Switch
//    수신자: notification-svc 가 payload 에 recipients[] 포함하여 전송
// ═══════════════════════════════════════════════════════════
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
        dashboardUrl: { defaultValue: dashboardBaseUrl, type: 'String' }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                event_type: { type: 'string' }
                severity:   { type: 'string' }
                payload:    { type: 'object' }
                // recipients: [{address, displayName}] — notification-svc 가 동적 결정
                recipients: { type: 'array' }
              }
              required: ['event_type', 'severity', 'payload', 'recipients']
            }
          }
        }
      }
      actions: {

        Switch_EventType: {
          type: 'Switch'
          expression: '@triggerBody()?[\'event_type\']'
          cases: {

            // ── 1. AI 자동 승인 알림 (CRITICAL · 즉시 · 본사) ──────────
            AutoExecutedUrgent: {
              case: 'AutoExecutedUrgent'
              actions: {
                Email_AutoExecutedUrgent: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '🤖 [특이] AI 자동 승인 @{triggerBody()?[\'payload\']?[\'n\']}건 · 본사 검토 필요'
                        html: '<p>07:00 batch가 긴급도/예측 근거로 본사 검토 없이 자동 승인했습니다.</p><ul><li>CRITICAL (@{triggerBody()?[\'payload\']?[\'critical\']}건): 가용 ≤ 0 + 24h 내 품절 예측</li><li>URGENT (@{triggerBody()?[\'payload\']?[\'urgent\']}건): 가용 &lt; 안전재고 + 7일 평균 판매 초과</li></ul><p>⚠️ 비용 발생 · 사후 회수 불가</p><p><a href="@{parameters(\'dashboardUrl\')}/decision?status=AUTO_EXECUTED&date=@{utcNow(\'yyyy-MM-dd\')}">자동 승인 내역 확인</a></p>'
                      }
                      importance: 'high'
                    }
                  }
                }
              }
            }

            // ── 2. 모든 PENDING 처리 완료 (INFO · 1회 · 본사+경영진+WH+지점 전체) ──
            DailyPlanFinalized: {
              case: 'DailyPlanFinalized'
              actions: {
                Email_DailyPlanFinalized: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '✅ [최종확정] @{triggerBody()?[\'payload\']?[\'today\']} 의사결정 모두 완료 · 운송 시작'
                        html: '<p>오늘 처리해야 할 의사결정이 모두 완료됐습니다 — 운송 시작 가능 상태.</p><ul><li>총 @{triggerBody()?[\'payload\']?[\'total\']}건 발의</li><li>✅ 승인 (자동+수동): @{triggerBody()?[\'payload\']?[\'approved\']}건</li><li>❌ 거절: @{triggerBody()?[\'payload\']?[\'rejected\']}건</li><li>자동 실행: @{triggerBody()?[\'payload\']?[\'auto\']}건</li></ul><p>Stage 1(권역 내): @{triggerBody()?[\'payload\']?[\'s1\']}건 · Stage 2(권역 간): @{triggerBody()?[\'payload\']?[\'s2\']}건 · Stage 3(발주): @{triggerBody()?[\'payload\']?[\'s3\']}건</p><p><a href="@{parameters(\'dashboardUrl\')}/decision?date=@{triggerBody()?[\'payload\']?[\'today\']}">최종 계획안 보기</a></p>'
                      }
                      importance: 'normal'
                    }
                  }
                }
              }
            }

            // ── 3. SNS 급등 (CRITICAL · 즉시 · 본사+양 권역매니저) ──────
            SpikeUrgent: {
              case: 'SpikeUrgent'
              actions: {
                Email_SpikeUrgent: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '🔥 [긴급] SNS 급등: "@{triggerBody()?[\'payload\']?[\'title\']}" (z-score @{triggerBody()?[\'payload\']?[\'z_score\']})'
                        html: '<p>SNS 화제 도서가 감지됐습니다. 24h 내 폭증 매출 가능성.</p><ul><li>📚 도서: @{triggerBody()?[\'payload\']?[\'title\']} (@{triggerBody()?[\'payload\']?[\'isbn13\']})</li><li>📈 z-score: @{triggerBody()?[\'payload\']?[\'z_score\']} · 멘션: @{triggerBody()?[\'payload\']?[\'mentions_count\']}회 · 카테고리: @{triggerBody()?[\'payload\']?[\'category\']}</li><li>🏪 안전재고 미달: @{triggerBody()?[\'payload\']?[\'shortage_stores\']}개 매장</li></ul><p><a href="@{parameters(\'dashboardUrl\')}/spikes">즉시 발의 화면</a></p>'
                      }
                      importance: 'high'
                    }
                  }
                }
              }
            }

            // ── 4. 양쪽 승인 24h+ 정체 (WARNING · 본사+양 권역매니저) ──
            ApprovalDelayed: {
              case: 'ApprovalDelayed'
              actions: {
                Email_ApprovalDelayed: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '⏳ [협의지연] 권역 이동 @{triggerBody()?[\'payload\']?[\'n\']}건 · 24h+ 양쪽 승인 대기'
                        html: '<p>권역 간 이동 협의가 24시간 이상 정체됐습니다.</p><ul><li>수도권→영남 대기 (영남 미승인): @{triggerBody()?[\'payload\']?[\'a\']}건</li><li>영남→수도권 대기 (수도권 미승인): @{triggerBody()?[\'payload\']?[\'b\']}건</li></ul><p><a href="@{parameters(\'dashboardUrl\')}/decision">본사 강제 승인</a> | <a href="@{parameters(\'dashboardUrl\')}/wh-transfer">WhTransfer 분석 뷰</a></p>'
                      }
                      importance: 'normal'
                    }
                  }
                }
              }
            }

            // ── 5. 매장 입고 거부 (WARNING · 5분 batch · 해당 권역매니저+본사) ──
            //    recipients: notification-svc 가 target_wh_id 로 해당 권역만 추출해 전달
            InboundRejected: {
              case: 'InboundRejected'
              actions: {
                Email_InboundRejected: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '📦 [입고거부] @{triggerBody()?[\'payload\']?[\'n\']}건 · 최근 5분 (@{triggerBody()?[\'payload\']?[\'region\']})'
                        html: '<p>@{triggerBody()?[\'payload\']?[\'region\']} 매장 입고 거부 @{triggerBody()?[\'payload\']?[\'n\']}건 발생 — 후속 조치 필요.</p><p>거부 사유: @{triggerBody()?[\'payload\']?[\'reasons\']}</p><p><a href="@{parameters(\'dashboardUrl\')}/wh-instructions?status=REJECTED">입고 거부 목록</a></p>'
                      }
                      importance: 'normal'
                    }
                  }
                }
              }
            }

            // ── 6. 출판사 신간 신청 (INFO · 즉시 · 본사만) ──────────────
            NewBookRequest: {
              case: 'NewBookRequest'
              actions: {
                Email_NewBookRequest: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '📚 [신간] 출판사 신간 신청 @{triggerBody()?[\'payload\']?[\'n\']}건 · 편입 결정 필요'
                        html: '<p>출판사에서 신간 판매 신청 @{triggerBody()?[\'payload\']?[\'n\']}건이 접수됐습니다.</p><p>본사 편입 결정 후 발주 지시서가 자동 발송됩니다.</p><p><a href="@{parameters(\'dashboardUrl\')}/requests">신간 편입 결정</a></p>'
                      }
                      importance: 'normal'
                    }
                  }
                }
              }
            }

            // ── 7. Lambda 장애 (CRITICAL · 즉시 · DevOps) ───────────────
            LambdaAlarm: {
              case: 'LambdaAlarm'
              actions: {
                Email_LambdaAlarm: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '🚨 [시스템] Lambda fail: @{triggerBody()?[\'payload\']?[\'function_name\']}'
                        html: '<p>🔧 Function: @{triggerBody()?[\'payload\']?[\'function_name\']}</p><p>⏰ @{triggerBody()?[\'payload\']?[\'timestamp\']}</p><p>❌ @{triggerBody()?[\'payload\']?[\'error_message\']}</p><p>📍 Request ID: @{triggerBody()?[\'payload\']?[\'request_id\']}</p><p>영향 범위: @{triggerBody()?[\'payload\']?[\'impact\']}</p><p><a href="@{triggerBody()?[\'payload\']?[\'cloudwatch_url\']}">CloudWatch Logs</a></p>'
                      }
                      importance: 'high'
                    }
                  }
                }
              }
            }

            // ── 8. 배포 롤백 (CRITICAL · 즉시 · DevOps) ─────────────────
            DeploymentRollback: {
              case: 'DeploymentRollback'
              actions: {
                Email_DeploymentRollback: {
                  type: 'Http'
                  operationOptions: 'DisableAsyncPattern'
                  inputs: {
                    method: 'POST'
                    uri: acsEmailUri
                    authentication: acsAuth
                    body: {
                      senderAddress: acsSenderAddress
                      recipients: {
                        to: '@triggerBody()?[\'recipients\']'
                      }
                      content: {
                        subject: '🔄 [배포] CodePipeline rollback: @{triggerBody()?[\'payload\']?[\'pipeline_name\']}'
                        html: '<p>CodePipeline이 자동 rollback 했습니다.</p><ul><li>🔧 Pipeline: @{triggerBody()?[\'payload\']?[\'pipeline_name\']}</li><li>🌿 Branch: @{triggerBody()?[\'payload\']?[\'branch\']} · Commit: @{triggerBody()?[\'payload\']?[\'commit_sha\']}</li><li>⏰ Rollback 시각: @{triggerBody()?[\'payload\']?[\'timestamp\']}</li><li>❌ 실패 단계: @{triggerBody()?[\'payload\']?[\'failed_stage\']}</li></ul><p>조치: 코드 변경 검토 + 재배포 결정</p><p><a href="@{triggerBody()?[\'payload\']?[\'codepipeline_url\']}">Pipeline 확인</a></p>'
                      }
                      importance: 'high'
                    }
                  }
                }
              }
            }

          }
          default: {
            actions: {}
          }
        }

        Response: {
          type: 'Response'
          runAfter: {
            Switch_EventType: ['Succeeded', 'Failed', 'Skipped', 'TimedOut']
          }
          inputs: {
            statusCode: 200
            body: { result: 'ok' }
          }
        }

      }
    }
    parameters: {}
  }
}

// ═══════════════════════════════════════════════════════════
// 2. Daily Digest Logic App — 매일 09:00 KST (= 00:00 UTC)
//    수신자: digestRecipients 파라미터 (본사+경영진+WH+지점 전체)
// ═══════════════════════════════════════════════════════════
resource logicAppDailyDigest 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-${prefix}-daily-digest'
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
        dashboardUrl:       { defaultValue: dashboardBaseUrl,  type: 'String' }
        digestRecipients:   { defaultValue: digestRecipients,  type: 'String' }
      }
      triggers: {
        Recurrence_0900KST: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: ['0']
              minutes: [0]
            }
            timeZone: 'UTC'
          }
        }
      }
      actions: {

        HTTP_Funnel: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'dashboardUrl\')}/dashboard/cascade/funnel?days=1'
          }
        }
        HTTP_PendingSummary: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'dashboardUrl\')}/dashboard/pending/summary?days=1'
          }
        }
        HTTP_Sales30: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'dashboardUrl\')}/dashboard/sales/30days'
          }
        }
        HTTP_Bestsellers: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'dashboardUrl\')}/dashboard/sales/bestsellers?days=1&limit=5'
          }
        }
        HTTP_Insufficient: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'dashboardUrl\')}/dashboard/forecast/insufficient?limit=5'
          }
        }

        Compose_DigestBody: {
          type: 'Compose'
          runAfter: {
            HTTP_Funnel:         ['Succeeded', 'Failed']
            HTTP_PendingSummary: ['Succeeded', 'Failed']
            HTTP_Sales30:        ['Succeeded', 'Failed']
            HTTP_Bestsellers:    ['Succeeded', 'Failed']
            HTTP_Insufficient:   ['Succeeded', 'Failed']
          }
          inputs: '<h2>📊 BookFlow 일일 요약 — @{formatDateTime(addDays(utcNow(), -1), \'yyyy-MM-dd\')} (KST)</h2><h3>🎯 핵심 KPI</h3><ul><li>전사 매출: ₩@{body(\'HTTP_Sales30\')?[\'revenue\']} (@{body(\'HTTP_Sales30\')?[\'delta\']}%)</li><li>거래 건수: @{body(\'HTTP_Sales30\')?[\'tx_count\']}건</li><li>결품률: @{body(\'HTTP_Insufficient\')?[\'shortage_rate\']}%</li></ul><h3>📦 의사결정 (어제)</h3><ul><li>총 @{body(\'HTTP_Funnel\')?[\'total\']}건 · 승인 @{body(\'HTTP_Funnel\')?[\'approved\']} · 거절 @{body(\'HTTP_Funnel\')?[\'rejected\']} · 자동실행 @{body(\'HTTP_Funnel\')?[\'auto\']}</li><li>Stage 1: @{body(\'HTTP_Funnel\')?[\'s1\']} · Stage 2: @{body(\'HTTP_Funnel\')?[\'s2\']} · Stage 3: @{body(\'HTTP_Funnel\')?[\'s3\']}</li></ul><h3>⚠️ 오늘 조치 필요</h3><ul><li>검토 필요 PENDING: @{body(\'HTTP_PendingSummary\')?[\'pending_count\']}건</li><li>재고 부족 도서: @{body(\'HTTP_Insufficient\')?[\'count\']}건</li></ul><h3>📚 어제 베스트셀러 Top5</h3><p>@{body(\'HTTP_Bestsellers\')?[\'items\']}</p><p><a href="@{parameters(\'dashboardUrl\')}/kpi">전사 KPI 차트</a></p>'
        }

        Send_DailyDigest: {
          type: 'Http'
          operationOptions: 'DisableAsyncPattern'
          runAfter: {
            Compose_DigestBody: ['Succeeded']
          }
          inputs: {
            method: 'POST'
            uri: acsEmailUri
            authentication: acsAuth
            body: {
              senderAddress: acsSenderAddress
              recipients: {
                to: '@json(parameters(\'digestRecipients\'))'
              }
              content: {
                subject: '📊 [일일요약] BookFlow @{formatDateTime(addDays(utcNow(), -1), \'yyyy-MM-dd\')}'
                html: '@{outputs(\'Compose_DigestBody\')}'
              }
              importance: 'normal'
            }
          }
        }

      }
    }
    parameters: {}
  }
}

// ═══════════════════════════════════════════════════════════
// 3. Plan Watcher Logic App — 매시간 PENDING=0 감지
//    수신자: digestRecipients 파라미터 (전 레벨 공유)
// ═══════════════════════════════════════════════════════════
resource logicAppPlanWatcher 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-${prefix}-plan-watcher'
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
        dashboardUrl:     { defaultValue: dashboardBaseUrl, type: 'String' }
        digestRecipients: { defaultValue: digestRecipients, type: 'String' }
      }
      triggers: {
        Recurrence_Hourly: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Hour'
            interval: 1
          }
        }
      }
      actions: {

        HTTP_GetPendingSummary: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'dashboardUrl\')}/dashboard/pending/summary?days=1'
          }
        }

        Check_AllPendingZero: {
          type: 'If'
          runAfter: {
            HTTP_GetPendingSummary: ['Succeeded']
          }
          expression: {
            and: [
              {
                equals: [
                  '@body(\'HTTP_GetPendingSummary\')?[\'pending_count\']'
                  0
                ]
              }
            ]
          }
          actions: {
            Email_PlanFinalized: {
              type: 'Http'
              operationOptions: 'DisableAsyncPattern'
              inputs: {
                method: 'POST'
                uri: acsEmailUri
                authentication: acsAuth
                body: {
                  senderAddress: acsSenderAddress
                  recipients: {
                    to: '@json(parameters(\'digestRecipients\'))'
                  }
                  content: {
                    subject: '✅ [최종확정] @{formatDateTime(utcNow(), \'yyyy-MM-dd\')} 의사결정 모두 완료 · 운송 시작'
                    html: '<p>오늘의 모든 PENDING이 처리됐습니다. 운송 시작 가능 상태입니다.</p><ul><li>총 @{body(\'HTTP_GetPendingSummary\')?[\'total\']}건 처리 완료</li></ul><p><a href="@{parameters(\'dashboardUrl\')}/decision?date=@{formatDateTime(utcNow(), \'yyyy-MM-dd\')}">최종 계획안 보기</a></p>'
                  }
                  importance: 'normal'
                }
              }
            }
          }
          else: {
            actions: {}
          }
        }

      }
    }
    parameters: {}
  }
}

// ═══════════════════════════════════════════════════════════
// 4. Secret Rotation Logic App — 매일 02:00 KST
//    수신자: digestRecipients 파라미터 (본사)
// ═══════════════════════════════════════════════════════════
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
      parameters: {
        digestRecipients: { defaultValue: digestRecipients, type: 'String' }
      }
      triggers: {
        Recurrence_0200KST: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: ['17']
              minutes: [0]
            }
            timeZone: 'UTC'
          }
        }
      }
      actions: {
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
        Notify_DevOps: {
          type: 'Http'
          operationOptions: 'DisableAsyncPattern'
          runAfter: {
            List_Secrets: ['Succeeded']
          }
          inputs: {
            method: 'POST'
            uri: acsEmailUri
            authentication: acsAuth
            body: {
              senderAddress: acsSenderAddress
              recipients: {
                to: '@json(parameters(\'digestRecipients\'))'
              }
              content: {
                subject: '[BOOKFLOW] Key Vault 시크릿 만료 점검 실행'
                html: '<p>Key Vault 시크릿 만료 점검이 실행됐습니다.</p><p>시크릿 목록: @{body(\'List_Secrets\')?[\'value\']}</p>'
              }
              importance: 'normal'
            }
          }
        }
      }
    }
    parameters: {}
  }
}

// ── 진단 설정 ─────────────────────────────────────────────
resource diagNotification 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-notification'
  scope: logicAppNotification
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

resource diagDailyDigest 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-daily-digest'
  scope: logicAppDailyDigest
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

resource diagPlanWatcher 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-plan-watcher'
  scope: logicAppPlanWatcher
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

resource diagRotation 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-la-rotation'
  scope: logicAppSecretRotation
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

// ── 출력값 ───────────────────────────────────────────────
output notificationLogicAppId string = logicAppNotification.id
output notificationLogicAppName string = logicAppNotification.name
output notificationTriggerUrl string = listCallbackUrl('${logicAppNotification.id}/triggers/manual', '2019-05-01').value

output dailyDigestLogicAppId string = logicAppDailyDigest.id
output dailyDigestLogicAppName string = logicAppDailyDigest.name

output planWatcherLogicAppId string = logicAppPlanWatcher.id
output planWatcherLogicAppName string = logicAppPlanWatcher.name

output rotationLogicAppId string = logicAppSecretRotation.id
output rotationLogicAppName string = logicAppSecretRotation.name
