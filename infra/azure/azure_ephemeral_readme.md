# Azure · Ephemeral (⏰ 삭제/재배포)

## 이 레이어의 역할

**비용 최적화를 위해 필요할 때만 올리고 쓰지 않을 때 내리는 자원들.**
`deploy-all.sh` 로 올리고 `cleanup-selective.sh` 로 내림.
Entra ID 앱·그룹과 PIP 2개는 건드리지 않음.

**라이프사이클**: ⏰ 실습/발표 시 `deploy-all.sh` → 종료 시 `cleanup-selective.sh`

---

## 자원 목록 (13개 · 의존성 역순 배포)

### 🔐 Security (1개)

| 자원 | 이름 | 비고 |
|---|---|---|
| Key Vault | `kv-bookflow` | Purge Protection ON → 삭제 시 soft-delete 90일. 재배포 시 자동 복구, 시크릿 보존 |

### 🌐 Foundation (5개)

| 자원 | 이름 | 비고 |
|---|---|---|
| 관리 ID (Function) | `id-bookflow-function` | 재생성 시 Principal ID 변경 → Key Vault RBAC 자동 재할당 |
| 관리 ID (LogicApp) | `id-bookflow-logicapp` | 동일 |
| NSG (Services) | `nsg-bookflow-services` | 상태 없음, 즉시 재배포 가능 |
| NSG (Function) | `nsg-bookflow-function` | 상태 없음, 즉시 재배포 가능 |
| VNet | `vnet-bookflow` | 서브넷 3개 포함 (GatewaySubnet · snet-services · snet-function) |

### 📊 Observability (1개)

| 자원 | 이름 | 비고 |
|---|---|---|
| Log Analytics Workspace | `law-bookflow` | 삭제 시 과거 로그 유실. 재배포 시 새 워크스페이스로 시작 |

### ⚙ Compute (3개)

| 자원 | 이름 | 비고 |
|---|---|---|
| Function App | `func-bookflow-sync` | 재배포 후 `func azure functionapp publish` 코드 재업로드 필요 |
| App Service Plan | `asp-bookflow` | Consumption (Y1) · Linux · 실행 기반 과금 |
| Storage Account | `stbookflowfunc` | Function App 런타임 스토리지 |

### 🔗 Integration (2개)

| 자원 | 이름 | 비고 |
|---|---|---|
| Event Grid System Topic | `egt-bookflow-keyvault` | Key Vault 이벤트 소스. 구독은 Portal에서 수동 연결 |
| Logic Apps (알림) | `la-bookflow-notification` | 재배포 후 Teams·Outlook 커넥터 Portal 수동 인증 필요 |
| Logic Apps (교체) | `la-bookflow-secret-rotation` | 재배포 후 Outlook 커넥터 Portal 수동 인증 필요 |

### 🛡 Network — VPN (1개 · 가장 비쌈)

| 자원 | 이름 | 비고 |
|---|---|---|
| VPN Gateway | `vpngw-bookflow` | VpnGw1AZ · BGP ON · Active/Standby. **PIP는 별도 영구 자원** |

---

## 배포 순서 (deploy-all.sh 내부 순서)

```
STACK 1 · Foundation
  1. 관리 ID (id-bookflow-function · id-bookflow-logicapp)
  2. NSG (nsg-bookflow-services · nsg-bookflow-function)
  3. Log Analytics (law-bookflow)
  4. VNet (vnet-bookflow)                    ← NSG ID 필요

STACK 2 · Security
  5. Key Vault (kv-bookflow)                 ← 관리 ID Principal ID 필요
                                               soft-delete 상태면 자동 복구

STACK 3 · Compute
  6. Function App (func-bookflow-sync)       ← Key Vault URI 필요
  7. Function 코드 배포                      ← func azure functionapp publish

STACK 4 · Integration
  8. Event Grid (egt-bookflow-keyvault)      ← Key Vault ID 필요

STACK 5 · Automation
  9. Logic Apps (la-bookflow-*)              ← Key Vault URI · 관리 ID 필요

STACK 6 · Network
  10. VPN Gateway (vpngw-bookflow)           ← GatewaySubnet ID 필요 (30~45분 소요)
```

의존성이 있는 핵심 체인: **관리 ID → Key Vault → Function App / Logic Apps**

---

## 삭제 순서 (cleanup-selective.sh 내부 순서)

배포 역순으로 삭제해야 의존성 충돌 없음:

```
1. VPN Connection (conn-bookflow-aws-active)    ← VPN Gateway 삭제 전
2. Local Network Gateway (lng-bookflow-aws-active)
3. VPN Gateway (vpngw-bookflow)                 ← PIP는 유지
4. Logic Apps × 2
5. Event Grid (egt-bookflow-keyvault)
6. Function App (func-bookflow-sync)
7. App Service Plan (asp-bookflow)
8. Storage Account (stbookflowfunc)
9. Key Vault (kv-bookflow)                      ← soft-delete 전환
10. Log Analytics (law-bookflow)
11. VNet (vnet-bookflow)                        ← VPN Gateway 삭제 후
12. NSG × 2
13. 관리 ID × 2
14. ARM 배포 이력 삭제                          ← 재배포 시 skip 방지
```

---

## 재배포 후 수동 작업

### 1. Logic App 커넥터 인증 (Portal)

```
la-bookflow-notification
  → 논리 앱 디자이너 → Send_Teams_Message 교체
    : 작업 추가 → Microsoft Teams → "채널에 메시지 게시" → 로그인
  → Send_Outlook_Email 교체
    : 작업 추가 → Office 365 Outlook → "전자 메일 보내기(V2)" → 로그인
  → 저장

la-bookflow-secret-rotation
  → 논리 앱 디자이너 → Notify_Admin 교체
    : 작업 추가 → Office 365 Outlook → 로그인
  → 저장
```

### 2. Function 코드 재배포

```bash
cd functions/sync-secret
func azure functionapp publish func-bookflow-sync --python
```

### 3. VPN 재연결 (AWS 팀 준비 완료 후)

```bash
bash scripts/vpn-connect.sh
# → AWS TGW Active IP · BGP Peering IP · PSK 입력
```

---

## 다른 레이어와의 관계

| 의존 방향 | 내용 |
|---|---|
| 영구 자원 → 이 레이어 | PIP 2개를 VPN Gateway가 재사용 (IP 불변) |
| 영구 자원 → 이 레이어 | Entra Client ID를 Key Vault 시크릿으로 Function App이 참조 |
| 이 레이어 → AWS | func-bookflow-sync가 AWS API Gateway URL로 시크릿 동기화 |
| 이 레이어 → AWS | la-bookflow-notification이 AWS SNS 이벤트 수신 후 Teams 발송 |

---

## 검증

```bash
# 전체 리소스 배포 확인
az resource list --resource-group rg-bookflow \
  --query "[].{name:name, type:type}" --output table

# Key Vault 상태
az keyvault show --resource-group rg-bookflow --name kv-bookflow \
  --query "{name:name, softDelete:properties.enableSoftDelete, purge:properties.enablePurgeProtection}" \
  --output table

# Function App 상태
az functionapp show --resource-group rg-bookflow --name func-bookflow-sync \
  --query "{name:name, state:state}" --output table

# Logic Apps 상태
az logic workflow list --resource-group rg-bookflow \
  --query "[].{name:name, state:state}" --output table

# VPN Gateway 상태
az network vnet-gateway show --resource-group rg-bookflow --name vpngw-bookflow \
  --query "{name:name, state:provisioningState}" --output table
```

---

## 비용 추정

| 자원 | 시간당 | 월 비용 (기준: 하루 8시간 × 22일) |
|---|---|---|
| **VPN Gateway (VpnGw1AZ)** | ~$0.35 | **~$61.60** (가장 큰 비용) |
| Log Analytics (PerGB2018) | 수집량 기준 | ~$2~5 (소량 로그) |
| Function App (Consumption Y1) | 실행 기준 | ~$0 (비활성 시) |
| App Service Plan (Y1) | $0 | $0 (Consumption) |
| Storage Account (Standard LRS) | ~$0.001 | ~$0.02 |
| Logic Apps | 액션 기준 | ~$0 (비활성 시) |
| NSG · VNet · 관리 ID | $0 | $0 |
| Key Vault (Standard) | 요청 기준 | ~$0 (비활성 시) |

**전체 삭제 시 VPN Gateway 삭제만으로 월 약 $60 절감.**
PIP 2개(영구 유지)는 월 $7.30 고정 발생.

## 비고

- Key Vault는 삭제해도 soft-delete 상태로 90일 유지 → 시크릿 보존. `deploy-all.sh` 재실행 시 자동 복구
- 관리 ID 재생성 시 Principal ID가 변경되지만 Bicep이 새 RBAC 할당을 자동 생성함
- Logic Apps 커넥터 인증은 재배포마다 수동 재설정 필요 (Bicep으로 자동화 불가)
