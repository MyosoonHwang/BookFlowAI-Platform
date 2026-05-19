#!/usr/bin/env bash
# acs-rate-limit-test.sh
#
# ACS Rate Limit 장애 시나리오 테스트
# 재현 단계 + 해결 검증 단계를 순서대로 실행
#
# 사용법:
#   bash acs-rate-limit-test.sh           # 재현 + 해결검증 전체 실행
#   bash acs-rate-limit-test.sh reproduce  # 재현 단계만
#   bash acs-rate-limit-test.sh verify     # 해결검증 단계만
#   bash acs-rate-limit-test.sh cancel     # Running 상태 Logic App 강제 취소
#
# 사전 조건:
#   kubectl, python3(httpx), az CLI 로그인 상태
#
# 환경 변수 (선택):
#   NOTIFICATION_PORT   port-forward 로컬 포트 (기본: 18080)
#   AZURE_SUB           Azure 구독 ID (기본: e98a94bb-7532-4e49-8a36-bc42e30d5a81)
#   AZURE_RG            Azure 리소스 그룹 (기본: rg-bookflow)
#   SEND_COUNT          동시 발송 건수 (기본: 15)

set -euo pipefail

# ── 설정 ──────────────────────────────────────────────────────────
NOTIFICATION_PORT="${NOTIFICATION_PORT:-18080}"
AZURE_SUB="${AZURE_SUB:-e98a94bb-7532-4e49-8a36-bc42e30d5a81}"
AZURE_RG="${AZURE_RG:-rg-bookflow}"
SEND_COUNT="${SEND_COUNT:-15}"
NAMESPACE="bookflow"
SVC="notification-svc"
LOGIC_APP_DEPART="la-bookflowmj-stock-depart"
LOGIC_APP_ARRIVAL="la-bookflowmj-stock-arrival"
PF_PID=""

# ── 색상 출력 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}════════════════════════════════════════${NC}"; }

# ── 종료 시 port-forward 정리 ────────────────────────────────────
cleanup() {
    if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" 2>/dev/null; then
        info "port-forward 종료 (PID $PF_PID)"
        kill "$PF_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ── port-forward 시작 ────────────────────────────────────────────
start_port_forward() {
    info "port-forward 시작: $SVC → localhost:$NOTIFICATION_PORT"
    kubectl port-forward -n "$NAMESPACE" "svc/$SVC" "${NOTIFICATION_PORT}:80" &>/dev/null &
    PF_PID=$!
    sleep 3

    # 연결 확인
    if python3 -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://127.0.0.1:${NOTIFICATION_PORT}/health', timeout=5)
    sys.exit(0 if r.status == 200 else 1)
except Exception as e:
    print(f'health check failed: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
        ok "port-forward 연결 확인"
    else
        error "notification-svc health check 실패. 파드 상태 확인:"
        kubectl get pods -n "$NAMESPACE" -l app=notification-svc
        exit 1
    fi
}

# ── Python 동시 발송 스크립트 ────────────────────────────────────
run_concurrent_send() {
    local mode="${1:-normal}"   # normal | expect_fail
    local count="${2:-$SEND_COUNT}"

    python3 - <<PYEOF
import asyncio, httpx, time, uuid, sys

URL      = "http://127.0.0.1:${NOTIFICATION_PORT}/notification/send"
HEADERS  = {"Content-Type":"application/json","Authorization":"Bearer mock-token-system"}
COUNT    = $count
MODE     = "$mode"

results = []

async def send_one(session, i):
    payload = {
        "event_type": "StockDepartPending",
        "severity": "WARNING",
        "correlation_id": str(uuid.uuid4()),
        "recipients": [],
        "channels": "email",
        "payload_summary": {
            "isbn13": f"9780000{i:06d}",
            "source_wh_id": 1,
            "dest_store_id": i,
            "qty": 10,
        },
    }
    t0 = time.monotonic()
    try:
        r = await session.post(URL, headers=HEADERS, json=payload, timeout=30.0)
        elapsed = time.monotonic() - t0
        body = r.json()
        status = body.get("status", "?")
        results.append((i, r.status_code, elapsed, status))
        print(f"  [{i:02d}] HTTP {r.status_code}  {elapsed:.2f}s  status={status}")
    except Exception as e:
        elapsed = time.monotonic() - t0
        results.append((i, 0, elapsed, "ERROR"))
        print(f"  [{i:02d}] ERROR  {elapsed:.2f}s  {e}", file=sys.stderr)

async def main():
    print(f"\n  발송 시작: {time.strftime('%H:%M:%S')}  ({COUNT}건 동시)")
    t_start = time.monotonic()
    async with httpx.AsyncClient() as s:
        await asyncio.gather(*[send_one(s, i) for i in range(1, COUNT + 1)])
    total = time.monotonic() - t_start

    sent   = sum(1 for r in results if r[3] == "SENT")
    failed = sum(1 for r in results if r[3] in ("FAILED","ERROR"))
    min_e  = min(r[2] for r in results)
    max_e  = max(r[2] for r in results)

    print(f"\n  완료: {time.strftime('%H:%M:%S')}  total={total:.2f}s")
    print(f"  결과: SENT={sent}  FAILED={failed}  elapsed={min_e:.2f}s~{max_e:.2f}s")

    # 직렬화 여부 판단 (spread > 3s면 세마포어 동작 중)
    spread = max_e - min_e
    if spread > 3.0:
        print(f"  [SERIAL] spread={spread:.2f}s → Semaphore 직렬화 확인")
    else:
        print(f"  [CONCURRENT] spread={spread:.2f}s → 동시 처리 (Semaphore 미적용 또는 응답 빠름)")

    # 모드별 종료 코드
    if MODE == "expect_fail":
        sys.exit(0)   # 재현 단계는 실패해도 정상
    else:
        sys.exit(0 if failed == 0 else 1)

asyncio.run(main())
PYEOF
}

# ── Logic App Running 건수 조회 ──────────────────────────────────
check_logic_app_running() {
    info "Logic App Running 상태 조회 중..."
    local total=0
    for wf in "$LOGIC_APP_DEPART" "$LOGIC_APP_ARRIVAL"; do
        local url="https://management.azure.com/subscriptions/${AZURE_SUB}/resourceGroups/${AZURE_RG}/providers/Microsoft.Logic/workflows/${wf}/runs?api-version=2016-06-01&\$top=100&\$filter=status eq 'Running'"
        local count
        count=$(az rest --method get --url "$url" \
            --query 'length(value)' --output tsv 2>/dev/null || echo "0")
        echo "  [$wf] Running: ${count}건"
        total=$((total + count))
    done
    echo "  합계: ${total}건"
    echo "$total"
}

# ── Logic App Running 강제 취소 ──────────────────────────────────
cancel_running_logic_apps() {
    section "Running Logic App 강제 취소"
    local cancelled=0
    for wf in "$LOGIC_APP_DEPART" "$LOGIC_APP_ARRIVAL"; do
        local url="https://management.azure.com/subscriptions/${AZURE_SUB}/resourceGroups/${AZURE_RG}/providers/Microsoft.Logic/workflows/${wf}/runs?api-version=2016-06-01&\$top=100&\$filter=status eq 'Running'"
        local run_ids
        mapfile -t run_ids < <(az rest --method get --url "$url" \
            --query 'value[*].name' --output tsv 2>/dev/null)

        if [[ ${#run_ids[@]} -eq 0 ]]; then
            ok "[$wf] Running 없음"
            continue
        fi

        warn "[$wf] ${#run_ids[@]}건 취소 중..."
        for run_id in "${run_ids[@]}"; do
            local cancel_url="https://management.azure.com/subscriptions/${AZURE_SUB}/resourceGroups/${AZURE_RG}/providers/Microsoft.Logic/workflows/${wf}/runs/${run_id}/cancel?api-version=2016-06-01"
            az rest --method post --url "$cancel_url" --output none 2>/dev/null && \
                { echo "  취소: $run_id"; ((cancelled++)); } || \
                warn "  취소 실패: $run_id"
        done
    done
    ok "총 ${cancelled}건 취소 완료"
}

# ── notifications_log FAILED 조회 ───────────────────────────────
check_notifications_log() {
    info "notifications_log FAILED 확인 (최근 10분)..."
    echo "  아래 SQL을 RDS에서 직접 실행하세요:"
    echo ""
    echo "  SELECT event_type, status, COUNT(*) AS cnt, MIN(sent_at) AS first_fail"
    echo "  FROM notifications_log"
    echo "  WHERE status = 'FAILED'"
    echo "    AND sent_at > NOW() - INTERVAL '10 minutes'"
    echo "  GROUP BY event_type, status;"
}

# ════════════════════════════════════════════════════════════════
# 재현 단계
# ════════════════════════════════════════════════════════════════
run_reproduce() {
    section "재현 단계 — ACS Rate Limit 장애 재현"
    echo "  목적: 세마포어 없는 환경에서 다수 동시 발송 시 Logic App 429 재현 확인"
    echo "  (현재 파드에 이미 세마포어가 적용되어 있으면 재현이 안 될 수 있음)"
    echo ""

    start_port_forward

    section "1/3  ${SEND_COUNT}건 동시 발송"
    run_concurrent_send "expect_fail" "$SEND_COUNT" || true

    section "2/3  Logic App Running 상태 확인 (발송 직후 30초 대기)"
    sleep 30
    local running_count
    running_count=$(check_logic_app_running | tail -1)

    if [[ "$running_count" -gt 0 ]]; then
        warn "Running Logic App ${running_count}건 감지 → 429 재시도 루프 재현 성공"
        echo ""
        echo "  다음 명령으로 취소 가능:"
        echo "    bash $0 cancel"
    else
        ok "Running Logic App 없음 (세마포어가 이미 적용되어 정상 처리됨)"
    fi

    section "3/3  notifications_log 확인"
    check_notifications_log
}

# ════════════════════════════════════════════════════════════════
# 해결 검증 단계
# ════════════════════════════════════════════════════════════════
run_verify() {
    section "해결 검증 단계 — Semaphore(1) 적용 후 검증"
    echo "  목적: 15건 동시 발송 시 직렬 처리되어 429 없이 전부 SENT 확인"
    echo "  기대: elapsed spread > 3s (순차), 전부 SENT, Logic App Running 없음"
    echo ""

    start_port_forward

    section "1/3  ${SEND_COUNT}건 동시 발송"
    if run_concurrent_send "normal" "$SEND_COUNT"; then
        ok "전체 SENT 확인"
    else
        error "FAILED 발생 — 로그 확인 필요"
        exit 1
    fi

    section "2/3  Logic App Running 잔류 확인"
    sleep 5
    local running_count
    running_count=$(check_logic_app_running | tail -1)

    if [[ "$running_count" -eq 0 ]]; then
        ok "Running Logic App 없음 → 429 없이 정상 완료"
    else
        warn "Running ${running_count}건 잔류 — 확인 필요"
    fi

    section "3/3  검증 결과 요약"
    echo ""
    ok "세마포어 동작 확인:"
    echo "  - elapsed spread > 3s  → Logic Apps 직렬 처리"
    echo "  - 전부 HTTP 200 SENT   → ACS 429 없음"
    echo "  - Logic App Running 0건 → 무한 재시도 없음"
    echo ""
    check_notifications_log
}

# ════════════════════════════════════════════════════════════════
# 메인
# ════════════════════════════════════════════════════════════════
MODE="${1:-all}"

case "$MODE" in
    reproduce)
        run_reproduce
        ;;
    verify)
        run_verify
        ;;
    cancel)
        cancel_running_logic_apps
        ;;
    all)
        section "ACS Rate Limit 장애 시나리오 — 전체 실행"
        echo "  순서: 재현 단계 → 해결 검증 단계"
        echo ""
        run_reproduce
        echo ""
        warn "재현 단계 완료. Running Logic App이 있으면 먼저 취소 후 검증합니다."
        cancel_running_logic_apps
        echo ""
        run_verify
        ;;
    *)
        echo "사용법: $0 [reproduce|verify|cancel|all]"
        exit 1
        ;;
esac

section "완료"
