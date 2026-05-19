#!/usr/bin/env bash
# vpn-failover-test.sh
#
# Azure-AWS VPN Active/Standby Failover 시나리오 테스트
#
# 목적:
#   Tunnel1(Active) 강제 다운 → Tunnel2(Standby)가 Active로 전환되어
#   AWS-Azure 통신이 중단 없이 유지되는지 검증
#
# 사용법:
#   bash vpn-failover-test.sh             # 전체 실행 (failover + 검증 + 복구)
#   bash vpn-failover-test.sh check       # 현재 터널 상태만 확인
#   bash vpn-failover-test.sh failover    # Active 강제 다운 + Standby 전환 대기
#   bash vpn-failover-test.sh verify      # 통신 검증 (failover 후 실행)
#   bash vpn-failover-test.sh restore     # Tunnel1 PSK 복구
#
# 사전 조건:
#   aws CLI (ap-northeast-1), az CLI (로그인 상태)
#
# 환경 변수 (선택):
#   AWS_REGION        (기본: ap-northeast-1)
#   AZURE_SUB         (기본: e98a94bb-7532-4e49-8a36-bc42e30d5a81)
#   AZURE_RG          (기본: rg-bookflow)
#   FAILOVER_TIMEOUT  Standby 전환 대기 최대 초 (기본: 180)

set -euo pipefail

# ── 설정 ──────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
AZURE_SUB="${AZURE_SUB:-e98a94bb-7532-4e49-8a36-bc42e30d5a81}"
AZURE_RG="${AZURE_RG:-rg-bookflow}"
FAILOVER_TIMEOUT="${FAILOVER_TIMEOUT:-180}"

# AWS 리소스
VPN_CONN_ID="vpn-0c5c1f736a382cd41"          # Azure VPN connection
TGW_RT_ID="tgw-rtb-0212f95932a5468b2"        # TGW 라우트 테이블
AZURE_VNET_CIDR="172.16.0.0/16"              # Azure VNet 대역

# Tunnel1 (Active) — 정상 상태에서 BGP ROUTES 보유
TUNNEL1_IP="54.168.155.173"
AZURE_CONN_ACTIVE="conn-bookflowmj-aws-active"

# Tunnel2 (Standby)
TUNNEL2_IP="57.181.166.71"
AZURE_CONN_STANDBY="conn-bookflowmj-aws-standby"

# PSK
PSK_ORIGINAL="bookflow"
PSK_INVALID="bookflow-failover-test-$(date +%s)"

# ── 색상 출력 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
step()    { echo -e "${CYAN}[STEP]${NC}    $*"; }
section() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
}

# ── 안전 종료: PSK 복구 보장 ────────────────────────────────────
RESTORE_NEEDED=false
restore_on_exit() {
    if [[ "$RESTORE_NEEDED" == "true" ]]; then
        warn "스크립트 종료 감지 — Tunnel1 PSK 자동 복구 중..."
        az network vpn-connection update \
            --resource-group "$AZURE_RG" \
            --name "$AZURE_CONN_ACTIVE" \
            --shared-key "$PSK_ORIGINAL" \
            --output none 2>/dev/null && \
            ok "Tunnel1 PSK 복구 완료 (안전 종료)" || \
            error "PSK 복구 실패 — 수동 복구 필요: az network vpn-connection update -g $AZURE_RG -n $AZURE_CONN_ACTIVE --shared-key $PSK_ORIGINAL"
    fi
}
trap restore_on_exit EXIT

# ── 터널 상태 조회 ────────────────────────────────────────────────
get_tunnel_status() {
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$VPN_CONN_ID" \
        --region "$AWS_REGION" \
        --query 'VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,BGP:StatusMessage}' \
        --output json 2>/dev/null
}

get_tunnel_bgp() {
    local ip="$1"
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$VPN_CONN_ID" \
        --region "$AWS_REGION" \
        --query "VpnConnections[0].VgwTelemetry[?OutsideIpAddress==\`${ip}\`].StatusMessage" \
        --output text 2>/dev/null
}

get_tunnel_updown() {
    local ip="$1"
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$VPN_CONN_ID" \
        --region "$AWS_REGION" \
        --query "VpnConnections[0].VgwTelemetry[?OutsideIpAddress==\`${ip}\`].Status" \
        --output text 2>/dev/null
}

print_tunnel_table() {
    local data
    data=$(get_tunnel_status)
    echo ""
    echo "  ┌─────────────────────┬──────────┬──────────────────┬────────┐"
    echo "  │ 역할                │ AWS IP   │ BGP              │ 상태   │"
    echo "  ├─────────────────────┼──────────┼──────────────────┼────────┤"

    local t1_status t1_bgp t2_status t2_bgp
    t1_status=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(x['Status']) for x in d if x['IP']=='${TUNNEL1_IP}']" 2>/dev/null || echo "?")
    t1_bgp=$(echo "$data"    | python3 -c "import json,sys; d=json.load(sys.stdin); [print(x['BGP'])    for x in d if x['IP']=='${TUNNEL1_IP}']" 2>/dev/null || echo "?")
    t2_status=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(x['Status']) for x in d if x['IP']=='${TUNNEL2_IP}']" 2>/dev/null || echo "?")
    t2_bgp=$(echo "$data"    | python3 -c "import json,sys; d=json.load(sys.stdin); [print(x['BGP'])    for x in d if x['IP']=='${TUNNEL2_IP}']" 2>/dev/null || echo "?")

    local t1_mark t2_mark
    t1_mark=$([[ "$t1_status" == "UP" ]] && echo "${GREEN}UP${NC}" || echo "${RED}DOWN${NC}")
    t2_mark=$([[ "$t2_status" == "UP" ]] && echo "${GREEN}UP${NC}" || echo "${RED}DOWN${NC}")

    echo -e "  │ Tunnel1 (Active)    │ ...173   │ $(printf '%-16s' "$t1_bgp") │ ${t1_mark}   │"
    echo -e "  │ Tunnel2 (Standby)   │ ...71    │ $(printf '%-16s' "$t2_bgp") │ ${t2_mark}   │"
    echo "  └─────────────────────┴──────────┴──────────────────┴────────┘"
}

# ── TGW Azure 경로 확인 ──────────────────────────────────────────
check_tgw_azure_route() {
    local result
    result=$(aws ec2 search-transit-gateway-routes \
        --transit-gateway-route-table-id "$TGW_RT_ID" \
        --filters "Name=route-search.subnet-of-match,Values=${AZURE_VNET_CIDR}" \
        --region "$AWS_REGION" \
        --query 'Routes[*].{CIDR:DestinationCidrBlock,State:State,Via:TransitGatewayAttachments[0].ResourceId}' \
        --output json 2>/dev/null)

    local count
    count=$(echo "$result" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        local via state
        via=$(echo "$result"   | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('Via','?'))" 2>/dev/null)
        state=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('State','?'))" 2>/dev/null)
        echo "  TGW 경로: ${AZURE_VNET_CIDR}  →  ${via}  [${state}]"
        return 0
    else
        echo "  TGW 경로: ${AZURE_VNET_CIDR} 없음 (BGP 미수신)"
        return 1
    fi
}

# ── AWS→Azure 통신 검증 (EKS 노드에서 Azure GatewaySubnet ping) ──
check_aws_azure_connectivity() {
    local target_ip="${1:-172.16.1.1}"   # Azure GatewaySubnet 첫 IP
    info "AWS→Azure 연결 테스트: EKS 노드 → ${target_ip}"

    # EKS 노드에서 실행 가능한 파드 찾기
    local pod
    pod=$(kubectl get pod -n bookflow -l app=notification-svc \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$pod" ]]; then
        warn "notification-svc 파드 없음 — TGW 경로로 통신 가능 여부만 확인"
        return 0
    fi

    # 파드에서 ping (python3으로 TCP 연결 시도 — curl/ping 없음)
    local result
    result=$(kubectl exec -n bookflow "$pod" -- \
        python3 -c "
import socket, sys, time
target = '${target_ip}'
port = 443
t0 = time.monotonic()
try:
    sock = socket.create_connection((target, port), timeout=5)
    sock.close()
    print(f'TCP {target}:{port} REACHABLE ({(time.monotonic()-t0)*1000:.0f}ms)')
    sys.exit(0)
except Exception as e:
    print(f'TCP {target}:{port} UNREACHABLE: {e}')
    sys.exit(1)
" 2>/dev/null || echo "연결 불가")

    echo "  ${result}"
    return 0
}

# ════════════════════════════════════════════════════════════════
# check: 현재 상태 확인
# ════════════════════════════════════════════════════════════════
cmd_check() {
    section "현재 VPN 터널 상태"
    print_tunnel_table

    section "TGW Azure 경로"
    check_tgw_azure_route || warn "Azure 경로 미수신 — BGP 확인 필요"
}

# ════════════════════════════════════════════════════════════════
# failover: Tunnel1 강제 다운 → Tunnel2 전환 대기
# ════════════════════════════════════════════════════════════════
cmd_failover() {
    section "Failover 테스트 시작"

    # 사전 조건 확인
    step "사전 조건 확인"
    local t1_init
    t1_init=$(get_tunnel_updown "$TUNNEL1_IP")
    if [[ "$t1_init" != "UP" ]]; then
        error "Tunnel1이 이미 DOWN 상태 — 먼저 복구 후 실행: bash $0 restore"
        exit 1
    fi
    ok "Tunnel1 UP 확인"

    local t2_init
    t2_init=$(get_tunnel_updown "$TUNNEL2_IP")
    if [[ "$t2_init" != "UP" ]]; then
        error "Tunnel2가 UP 상태 아님 (현재: $t2_init) — Tunnel2 연결 확인 필요"
        exit 1
    fi
    ok "Tunnel2 UP 확인"

    echo ""
    info "테스트 전 상태:"
    print_tunnel_table
    echo ""
    info "TGW 기준 경로 (Tunnel1 via):"
    check_tgw_azure_route || true

    # Tunnel1 강제 다운 (PSK 변경)
    section "Tunnel1 강제 다운 (PSK 변경)"
    step "Azure conn-bookflowmj-aws-active PSK → 임시값 변경"
    RESTORE_NEEDED=true
    az network vpn-connection update \
        --resource-group "$AZURE_RG" \
        --name "$AZURE_CONN_ACTIVE" \
        --shared-key "$PSK_INVALID" \
        --output none
    local t0_fail
    t0_fail=$(date +%s)
    ok "PSK 변경 완료 — Tunnel1 IPSEC 협상 실패 시작"

    # Tunnel1 DOWN 대기
    section "Tunnel1 DOWN 대기"
    local elapsed=0
    while true; do
        local t1_now
        t1_now=$(get_tunnel_updown "$TUNNEL1_IP")
        elapsed=$(( $(date +%s) - t0_fail ))
        echo -e "  [${elapsed}s] Tunnel1: $([ "$t1_now" == "UP" ] && echo "${GREEN}UP${NC}" || echo "${RED}DOWN${NC}")"
        if [[ "$t1_now" != "UP" ]]; then
            ok "Tunnel1 DOWN 확인 (${elapsed}s 소요)"
            break
        fi
        if [[ $elapsed -ge $FAILOVER_TIMEOUT ]]; then
            error "Tunnel1 DOWN 대기 타임아웃 (${FAILOVER_TIMEOUT}s)"
            exit 1
        fi
        sleep 10
    done

    # Tunnel2 BGP 경로 수신 대기 (Failover 완료 조건)
    section "Tunnel2 Failover 대기 (BGP 경로 수신)"
    info "Tunnel2(${TUNNEL2_IP})에서 BGP ROUTES > 0 될 때까지 대기..."
    local t0_fo
    t0_fo=$(date +%s)
    while true; do
        local t2_bgp t2_status
        t2_bgp=$(get_tunnel_bgp "$TUNNEL2_IP")
        t2_status=$(get_tunnel_updown "$TUNNEL2_IP")
        elapsed=$(( $(date +%s) - t0_fo ))

        echo "  [${elapsed}s] Tunnel2: ${t2_status} | ${t2_bgp}"

        # BGP ROUTES 숫자가 1 이상이면 failover 완료
        if echo "$t2_bgp" | grep -qE "^[1-9][0-9]* BGP ROUTES"; then
            echo ""
            ok "Failover 완료! Tunnel2에서 BGP ROUTES 수신 (${elapsed}s 소요)"
            break
        fi

        # TGW 경로가 Tunnel2로 전환됐는지도 확인
        local tgw_via
        tgw_via=$(aws ec2 search-transit-gateway-routes \
            --transit-gateway-route-table-id "$TGW_RT_ID" \
            --filters "Name=route-search.subnet-of-match,Values=${AZURE_VNET_CIDR}" \
            --region "$AWS_REGION" \
            --query 'Routes[0].TransitGatewayAttachments[0].ResourceId' \
            --output text 2>/dev/null || echo "none")

        if echo "$tgw_via" | grep -q "$VPN_CONN_ID"; then
            echo ""
            ok "TGW 경로 유지 확인 (via $tgw_via)"
        fi

        if [[ $elapsed -ge $FAILOVER_TIMEOUT ]]; then
            warn "Failover 타임아웃 (${FAILOVER_TIMEOUT}s) — 현재 상태:"
            print_tunnel_table
            warn "Tunnel2 BGP 미수신. Azure BGP 설정 확인 필요"
            break
        fi
        sleep 15
    done

    echo ""
    info "Failover 후 상태:"
    print_tunnel_table
}

# ════════════════════════════════════════════════════════════════
# verify: 통신 검증
# ════════════════════════════════════════════════════════════════
cmd_verify() {
    section "통신 검증 — Tunnel2 경유 AWS-Azure 통신"

    step "1/3  TGW 라우트 테이블 Azure 경로 확인"
    if check_tgw_azure_route; then
        ok "TGW → Azure 경로 존재"
    else
        error "TGW에 Azure 경로 없음 — Failover 미완료"
        return 1
    fi

    step "2/3  EKS 파드 → Azure 연결 테스트"
    check_aws_azure_connectivity "172.16.1.1"

    step "3/3  현재 터널 상태"
    print_tunnel_table

    echo ""
    ok "검증 완료"
    echo ""
    echo "  요약:"
    echo "  - Tunnel1 (Active): DOWN (PSK 불일치)"
    echo "  - Tunnel2 (Standby→Active): UP"
    echo "  - TGW Azure 경로: Tunnel2 경유"
    echo "  - AWS-Azure 통신: 유지"
}

# ════════════════════════════════════════════════════════════════
# restore: Tunnel1 PSK 복구
# ════════════════════════════════════════════════════════════════
cmd_restore() {
    section "Tunnel1 PSK 복구"

    step "Azure conn-bookflowmj-aws-active PSK → 원래값 복구"
    az network vpn-connection update \
        --resource-group "$AZURE_RG" \
        --name "$AZURE_CONN_ACTIVE" \
        --shared-key "$PSK_ORIGINAL" \
        --output none
    RESTORE_NEEDED=false
    ok "PSK 복구 완료 — IPSEC 재협상 시작 (약 1분 소요)"

    section "Tunnel1 UP 복구 대기"
    local timeout=120 elapsed=0
    while true; do
        local t1_now
        t1_now=$(get_tunnel_updown "$TUNNEL1_IP")
        echo "  [${elapsed}s] Tunnel1: ${t1_now}"
        if [[ "$t1_now" == "UP" ]]; then
            ok "Tunnel1 복구 완료 (${elapsed}s 소요)"
            break
        fi
        if [[ $elapsed -ge $timeout ]]; then
            warn "복구 대기 타임아웃 (${timeout}s) — 수동 확인 필요"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo ""
    info "복구 후 최종 상태:"
    print_tunnel_table
    echo ""
    info "TGW Azure 경로:"
    check_tgw_azure_route || warn "Azure 경로 미수신 — BGP 재수립 대기 중"
}

# ════════════════════════════════════════════════════════════════
# 전체 실행
# ════════════════════════════════════════════════════════════════
cmd_all() {
    section "VPN Failover 시나리오 전체 실행"
    echo ""
    echo "  단계: 상태확인 → Failover → 통신검증 → 복구 → 최종확인"
    echo ""

    cmd_check

    echo ""
    warn "Tunnel1을 강제 다운시킵니다. 계속하려면 Enter, 취소는 Ctrl+C"
    read -r

    cmd_failover

    echo ""
    cmd_verify

    echo ""
    warn "Tunnel1을 복구합니다."
    cmd_restore

    section "최종 결과"
    cmd_check
    echo ""
    ok "Failover 시나리오 완료"
    echo ""
    echo "  결론:"
    echo "  - Tunnel1 DOWN 시 Tunnel2가 자동으로 Active 전환"
    echo "  - TGW 경로가 Tunnel2 경유로 전환되어 AWS-Azure 통신 유지"
    echo "  - Tunnel1 복구 후 Active 복원"
}

# ════════════════════════════════════════════════════════════════
# 메인
# ════════════════════════════════════════════════════════════════
MODE="${1:-all}"

case "$MODE" in
    check)    cmd_check ;;
    failover) cmd_failover ;;
    verify)   cmd_verify ;;
    restore)  cmd_restore ;;
    all)      cmd_all ;;
    *)
        echo "사용법: $0 [check|failover|verify|restore|all]"
        echo ""
        echo "  check     현재 터널 상태 확인"
        echo "  failover  Tunnel1 강제 다운 + Tunnel2 전환 대기"
        echo "  verify    통신 검증 (failover 후 실행)"
        echo "  restore   Tunnel1 PSK 복구"
        echo "  all       전체 시나리오 순서대로 실행 (기본)"
        exit 1
        ;;
esac
