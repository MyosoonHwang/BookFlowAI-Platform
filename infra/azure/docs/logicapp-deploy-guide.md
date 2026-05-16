# Logic Apps 배포 가이드

> **타입**: Consumption Logic App (`Microsoft.Logic/workflows`)
> **배포 방식**: `az rest PUT` + `arm-deploy.json` (envsubst 치환)
> **이유**: WS1 SKU 쿼터 = 0 → Standard 배포 불가, Consumption으로 전환

---

## 1. 워크플로 목록

| 워크플로 | 트리거 | 담당 이벤트 |
|---|---|---|
| `notification` | HTTP (SAS URL) | SpikeUrgent · NegotiationDelay · DailyPlanFinalized · InboundRejected |
| `approval-request` | HTTP (SAS URL) | ForecastCompleted |
| `stock-depart` | HTTP (SAS URL) | StockDepartPending |
| `stock-arrival` | HTTP (SAS URL) | StockArrivalPending |
| `delivery-completed` | HTTP (SAS URL) | DeliveryCompleted |
| `daily-digest` | Recurrence 09:00 KST | — (자체 스케줄) |

---

## 2. 이벤트 → Logic App 전체 흐름

### 이벤트 라우팅 맵

| event_type | Logic App | 수신자 | 성격 |
|---|---|---|---|
| `ForecastCompleted` | `approval-request` | 본사 + 물류 + 지점 | 수요예측 완료 → 발주계획 전원 승인 요청 |
| `SpikeUrgent` | `notification` | 본사 + 물류 | **외부 신호**: ECS SNS 급등 → 긴급발주 요청 |
| `NegotiationDelay` | `notification` | 협의 당사자 | **내부 지연**: 협의 병목 → 담당자 독촉 |
| `DailyPlanFinalized` | `notification` | 본사 + 물류 + 지점 | 당일 의사결정 완료 → 운송 시작 가능 알림 |
| `InboundRejected` | `notification` | 본사 + 물류 | 5분 배치 집계 후 입고 거부 건 알림 |
| `DeliveryCompleted` | `delivery-completed` | 입고 담당자 | **외부 입고**: 출판사→WH 외부 배송 완료 |
| `StockDepartPending` | `stock-depart` | **도착지** (지점·WH) | **내부 이동**: 출발지 출고 → 도착지 "오는 중" 알림 |
| `StockArrivalPending` | `stock-arrival` | **출발지** (지점·WH) | **내부 이동**: 도착지 수령 확인 → 출발지 "도착 완료" 알림 |
| `OrderPending` 등 | (없음) | — | Redis pub/sub(`order.*`)만 — Logic App 미트리거 |

> `OrderPending` / `OrderApproved` / `OrderDispatched` / `OrderExecuted` / `OrderRejected` 등
> order state machine 이벤트는 **Redis pub/sub 전용**. 이메일 발송 없음.

---

### 이벤트별 상세 흐름

#### ForecastCompleted — 발주계획 승인 요청
```
수요예측 배치 (1일 1회)
  → forecast-pod → notification-svc /notification/send
      event_type=ForecastCompleted
      payload: { snapshot_date, rows_created, by_stage }
      recipients: 본사 + 물류 + 지점
  → Logic App approval-request (SAS URL POST)
      Switch: ForecastCompleted case
  → ACS Email → 전원 (발주계획 승인 요청, 대시보드 링크)
```

#### SpikeUrgent — 긴급발주 요청
```
ECS SNS 모니터링 (spike-detect pod) - 외부 시장 신호
  → notification-svc /notification/send
      event_type=SpikeUrgent
      payload: { isbn13, title, location, current_stock, detected_at }
  → Logic App notification (SAS URL POST)
      Switch: SpikeUrgent case
  → ACS Email → 본사 + 물류 (긴급발주 요청, importance=high)
  + Redis publish → spike.detected 채널
```

#### NegotiationDelay — 협의지연 독촉
```
스케줄러 / 수동 트리거 - 내부 프로세스 병목
  → notification-svc /notification/send
      event_type=NegotiationDelay
  → Logic App notification (SAS URL POST)
      Switch: NegotiationDelay case
  → ACS Email → 협의 담당자 (처리 대기 항목 확인 요청)
```

#### DailyPlanFinalized — 운송 시작 가능 알림
```
당일 의사결정 완료 확인 후
  → notification-svc /notification/send
      event_type=DailyPlanFinalized
  → Logic App notification (SAS URL POST)
      Switch: DailyPlanFinalized case
  → ACS Email → 본사 + 물류 + 지점 (운송 시작 가능 안내)
```

#### StockDepartPending / StockArrivalPending — 내부 재고 이동
```
[출발지] 대시보드 출고버튼 클릭 → APPROVED → IN_TRANSIT
  → notification-svc (event_type=StockDepartPending)
  → Logic App stock-depart → ACS Email → 도착지 ("오는 중")

[도착지] 대시보드 수령확인 클릭 → IN_TRANSIT → EXECUTED
  → notification-svc (event_type=StockArrivalPending)
  → Logic App stock-arrival → ACS Email → 출발지 ("도착 완료")
```

#### DeliveryCompleted — 외부 입고 완료
```
물류업체 배송 완료 (출판사 → 물류센터)
  → notification-svc (event_type=DeliveryCompleted)
  → Logic App delivery-completed → ACS Email → 입고 담당자
```

#### daily-digest — 일일 발주 현황 (자체 스케줄)
```
매일 KST 09:00 자동 실행 (UTC 00:00 Recurrence)
  → GET /dashboard/cascade/funnel?days=1
  → [rejected > 0]
      GET /dashboard/decision/plan-daily/{today}/items?status=REJECTED
      → ACS Email → 본사만 (승인거부 지점·WH 확인 요청, importance=high)
  → [rejected=0, approved+executed > 0]
      → ACS Email → 전체 (최종 계획 확인 요청)
  → [처리 건 없음]
      → ACS Email → 전체 (일일 현황)
```

---

## 3. 배포 방법

### 전체 스택 재배포 (deploy-all.sh)

```bash
cd BookFlowAI-Platform/scripts/azure/1-daily
bash deploy-all.sh
```

STACK 5에서 아래 5개 Logic App을 순서대로 배포하고, 완료 후 SAS URL을 출력한다.

```
la-{PREFIX}-notification
la-{PREFIX}-approval-request
la-{PREFIX}-daily-digest
la-{PREFIX}-stock-depart
la-{PREFIX}-stock-arrival
```

### 단독 배포 (개별 Logic App)

```bash
# 환경변수 설정
export LOCATION="japanwest"
export LOGICAPP_IDENTITY_ID="/subscriptions/.../id-bookflowmj-logicapp"
export ACS_EMAIL_URI="https://acs-bookflowmj.japan.communication.azure.com/emails:send?api-version=2023-03-31"
export ACS_SENDER="DoNotReply@<domain>.azurecomm.net"
export DASHBOARD_URL="https://bookflow.myosoon.store"

SUB_ID=$(az account show --query id --output tsv)
LA_NAME="la-bookflowmj-approval-request"
TEMPLATE="infra/azure/workflows/approval-request/arm-deploy.json"

# envsubst 치환 후 az rest PUT
envsubst < "$TEMPLATE" > /tmp/la-arm.json
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/rg-bookflow/providers/Microsoft.Logic/workflows/${LA_NAME}?api-version=2016-06-01" \
  --body "@/tmp/la-arm.json"
```

---

## 4. SAS URL 발급

HTTP 트리거 Logic App(`notification`, `approval-request`, `stock-depart`, `stock-arrival`, `delivery-completed`)은 배포 후 SAS URL을 발급해야 한다.

```bash
SUB_ID=$(az account show --query id --output tsv)
RG="rg-bookflow"

for la_name in \
  la-bookflowmj-notification \
  la-bookflowmj-approval-request \
  la-bookflowmj-stock-depart \
  la-bookflowmj-stock-arrival \
  la-bookflowmj-delivery-completed; do
  echo "=== ${la_name} ==="
  az rest --method POST \
    --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Logic/workflows/${la_name}/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
    --query "value" --output tsv
done
```

---

## 5. notification-svc Secret 업데이트

> SAS URL은 인증키에 해당하므로 ConfigMap이 아닌 **Secret** (또는 ESO)에 보관해야 한다.
> 현재 ConfigMap에 임시 보관 중 → 운영 전 Secret으로 이관 필요.

발급한 SAS URL을 `eks-pods/notification-svc/k8s/configmap.yaml`에 설정 후 재배포:

```yaml
NOTIFICATION_LOGIC_APPS_URL:                    "<notification SAS URL>"
NOTIFICATION_LOGIC_APPS_APPROVAL_REQUEST_URL:   "<approval-request SAS URL>"
NOTIFICATION_LOGIC_APPS_STOCK_DEPART_URL:       "<stock-depart SAS URL>"
NOTIFICATION_LOGIC_APPS_STOCK_ARRIVAL_URL:      "<stock-arrival SAS URL>"
NOTIFICATION_LOGIC_APPS_DELIVERY_COMPLETED_URL: "<delivery-completed SAS URL>"
```

```bash
kubectl apply -f eks-pods/notification-svc/k8s/configmap.yaml -n bookflow
kubectl rollout restart deployment/notification-svc -n bookflow
kubectl rollout status deployment/notification-svc -n bookflow
```

---

## 6. 동작 확인

### Logic App 상태 확인
```bash
az logic workflow list \
  --resource-group rg-bookflow \
  --query "[].{name:name, state:properties.state}" \
  --output table
```

### ForecastCompleted 수동 테스트
```bash
SAS_URL="<approval-request SAS URL>"

curl -X POST "$SAS_URL" \
  -H "Content-Type: application/json" \
  --data-binary @- << 'EOF'
{
  "event_type": "ForecastCompleted",
  "severity": "INFO",
  "correlation_id": "test-forecast-001",
  "payload": {
    "snapshot_date": "2026-05-17",
    "rows_created": 38,
    "by_stage": {"0": 18, "1": 8, "2": 7, "3": 5}
  },
  "recipients": [
    {"address": "redfox@yonsei.ac.kr", "displayName": "본사"},
    {"address": "rladudgjs0427@gmail.com", "displayName": "물류"},
    {"address": "woohek00@gmail.com", "displayName": "지점"}
  ]
}
EOF
```

### SpikeUrgent 수동 테스트
```bash
SAS_URL="<notification SAS URL>"

curl -X POST "$SAS_URL" \
  -H "Content-Type: application/json" \
  --data-binary @- << 'EOF'
{
  "event_type": "SpikeUrgent",
  "severity": "CRITICAL",
  "payload": {
    "isbn13": "9791234567890",
    "title": "테스트 도서",
    "location": "강남 지점",
    "current_stock": 3,
    "detected_at": "2026-05-17 14:30"
  },
  "recipients": [
    {"address": "redfox@yonsei.ac.kr", "displayName": "본사"}
  ]
}
EOF
```

### 실행 기록 확인
```bash
# 최근 5회 실행 기록
SUB_ID=$(az account show --query id --output tsv)
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/rg-bookflow/providers/Microsoft.Logic/workflows/la-bookflowmj-approval-request/runs?api-version=2016-06-01&\$top=5" \
  --query "value[].{status:properties.status, startTime:properties.startTime}" \
  --output table
```
