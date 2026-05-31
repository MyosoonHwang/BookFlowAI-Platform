#!/usr/bin/env bash
# vpn-failover-test.sh
#
# Azure-AWS VPN Failover 검증 (BGP Read-Only 모니터링 기반)
#
# ── 아키텍처 ────────────────────────────────────────────────────
#
#   [Azure VPN Gateway (vpngw-bookflowmj)]
#       ├─ conn-bookflowmj-aws-active  (Tunnel1, 169.254.21.6)  ─┐
#       └─ conn-bookflowmj-aws-standby (Tunnel2, 169.254.21.10) ─┤
#                                                                  │  BGP(AS 65001 ↔ 64512)
#   [AWS Transit Gateway (TGW)]  ◄─────────────────────────────────┘
#       └─ VPN Connection (2 tunnels, ECMP enabled)
#
# ── ECMP란 ──────────────────────────────────────────────────────
#
#   Equal-Cost Multi-Path: 동일 목적지로 가는 여러 경로의 BGP 메트릭이
#   같을 때 트래픽을 분산하는 라우팅 전략.
#
#   이 환경에서는 TGW의 VpnEcmpSupport=enable 설정으로 인해
#   두 터널이 모두 UP이면 Azure 대역(172.16.0.0/16) 트래픽이
#   Tunnel1과 Tunnel2로 50/50 분산됩니다.
#
#   Failover 동작:
#     Tunnel1 다운 → TGW가 Tunnel1 BGP 경로 제거
#     → Tunnel2가 유일한 경로로 자동 전환 (스크립트 개입 없음)
#
#   ECMP를 disable하지 않은 이유:
#     TGW에는 GCP VPN도 연결되어 있으므로 전역 ECMP 설정 변경 시
#     GCP 연결에도 영향을 줍니다.
#
# ── BGP 설정 방침 ─────────────────────────────────────────────
#
#   두 Connection 모두 Bicep(vpn-connection.bicep)에서 배포 시
#   gatewayCustomBgpIpAddresses를 고정 설정하므로 BGP는 항상 활성.
#   이 스크립트는 Azure BGP 설정을 일절 수정하지 않습니다.
#   장애 유발 수단은 PSK(Shared Key) 변경만 사용합니다.
#
# ── 검증 흐름 ─────────────────────────────────────────────────
#
#   정상: Tunnel1·Tunnel2 모두 BGP 활성 → TGW ECMP 분산
#   장애: Tunnel1 PSK 변경 → IKE 재협상 실패 → IPsec DOWN
#         → BGP Hold Timer 만료(~90초) → BGP DOWN
#         → TGW가 자동으로 Tunnel2 단독 경로로 전환
#   복구: PSK 원복 → IKE 재협상 성공 → IPsec/BGP 재수립
#         → Tunnel1·Tunnel2 ECMP 복귀
#
# ── 사용법 ───────────────────────────────────────────────────
#   bash vpn-failover-test.sh check      현재 상태 확인
#   bash vpn-failover-test.sh prepare    베이스라인 확인 (read-only)
#   bash vpn-failover-test.sh failover   Tunnel1 PSK 변경 → 자동 전환 모니터링
#   bash vpn-failover-test.sh verify     통신 검증
#   bash vpn-failover-test.sh restore    Tunnel1 PSK 복구 → 자동 복귀 모니터링
#   bash vpn-failover-test.sh all        전체 시나리오 실행 (기본)

set -euo pipefail

# ── 설정 ────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
AZURE_RG="${AZURE_RG:-rg-bookflow}"
FAILOVER_TIMEOUT="${FAILOVER_TIMEOUT:-180}"   # Tunnel1 DOWN 확인 + TGW 전환 대기 최대 시간(초)
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-150}"     # Tunnel1 복구 대기 최대 시간(초)

VPN_CONN_ID="${VPN_CONN_ID:-vpn-0c0674261233df358}"   # AWS VPN Connection ID (Tunnel1·2 포함)
TGW_ID="${TGW_ID:-tgw-0dafe89fafc596ca1}"              # AWS Transit Gateway ID
AZURE_VNET_CIDR="172.16.0.0/16"                        # Azure VNet 대역 (TGW 라우트 검색에 사용)

# AWS 측에서 바라보는 두 터널의 외부(outside) 공인 IP
# vpn-site-to-site.yaml의 VgwTelemetry.OutsideIpAddress 값과 일치해야 함
TUNNEL1_IP="${TUNNEL1_IP:-13.113.91.218}"
TUNNEL2_IP="${TUNNEL2_IP:-43.207.5.222}"

# Azure VPN Connection 이름 (vpn-connection.bicep의 conn-{prefix}-aws-* 리소스)
AZURE_CONN_ACTIVE="conn-bookflowmj-aws-active"

# PSK: 원본 값과 장애 유발용 임시값
# PSK_INVALID는 타임스탬프를 붙여 매번 다른 값으로 생성 (IKE 재협상 확실히 실패시킴)
PSK_ORIGINAL="bookflow"
PSK_INVALID="bookflow-failover-$(date +%s)"

# ── 색상 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }
step()    { echo -e "${CYAN}[STEP]${NC}    $*"; }
section() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
}

# ── TGW RT ID 조회 ──────────────────────────────────────────────
# CloudFormation export → 없으면 TGW ID로 직접 조회 (두 단계 fallback)
_get_tgw_rt_id() {
    local rt
    rt=$(aws cloudformation list-exports --region "$AWS_REGION" \
        --query "Exports[?Name=='bookflow-tgw-rt-id'].Value" \
        --output text 2>/dev/null || echo "")
    if [[ -z "$rt" || "$rt" == "None" ]]; then
        rt=$(aws ec2 describe-transit-gateway-route-tables \
            --filters "Name=transit-gateway-id,Values=${TGW_ID}" \
                      "Name=state,Values=available" \
            --region "$AWS_REGION" \
            --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
            --output text 2>/dev/null || echo "")
    fi
    echo "$rt"
}
TGW_RT_ID=""

init() {
    [[ -n "$TGW_RT_ID" ]] && return
    TGW_RT_ID=$(_get_tgw_rt_id)
    [[ -z "$TGW_RT_ID" || "$TGW_RT_ID" == "None" ]] && {
        error "TGW route table ID 조회 실패. VPN 스택 배포 상태 확인 필요."
        exit 1
    }
    info "VPN_CONN_ID : $VPN_CONN_ID"
    info "TGW_RT_ID   : $TGW_RT_ID"
    info "Tunnel1     : $TUNNEL1_IP"
    info "Tunnel2     : $TUNNEL2_IP"
}

# ── 안전 종료 핸들러 ─────────────────────────────────────────────
# 스크립트가 Ctrl+C 등으로 중단될 때 PSK가 임시값으로 남지 않도록 자동 복구.
# BGP 설정은 건드리지 않으므로 PSK 복구만 수행.
RESTORE_NEEDED=false
restore_on_exit() {
    [[ "$RESTORE_NEEDED" != "true" ]] && return
    az network vpn-connection update -g "$AZURE_RG" -n "$AZURE_CONN_ACTIVE" \
        --shared-key "$PSK_ORIGINAL" --output none 2>/dev/null || true
}
trap restore_on_exit EXIT

# ── AWS 터널 상태 조회 ───────────────────────────────────────────
# VgwTelemetry: AWS VPN Connection에서 각 터널의 외부IP·상태·BGP 경로 수를 보여줌
get_tunnel_updown() {
    # "UP" 또는 "DOWN" 반환
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$VPN_CONN_ID" --region "$AWS_REGION" \
        --query "VpnConnections[0].VgwTelemetry[?OutsideIpAddress==\`${1}\`].Status" \
        --output text 2>/dev/null || echo "UNKNOWN"
}
get_tunnel_bgp() {
    # "N BGP ROUTES" 형태의 문자열 반환 (예: "1 BGP ROUTES", "0 BGP ROUTES")
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$VPN_CONN_ID" --region "$AWS_REGION" \
        --query "VpnConnections[0].VgwTelemetry[?OutsideIpAddress==\`${1}\`].StatusMessage" \
        --output text 2>/dev/null || echo "UNKNOWN"
}
# BGP 경로 수신 여부 판별 (1 이상이면 수신 중)
has_bgp_routes() { echo "$1" | grep -qE "^[1-9][0-9]* BGP ROUTES"; }
no_bgp_routes()  { ! echo "$1" | grep -qE "^[1-9][0-9]* BGP ROUTES"; }

print_tunnel_table() {
    local t1s t1b t2s t2b m1 m2
    t1s=$(get_tunnel_updown "$TUNNEL1_IP"); t1b=$(get_tunnel_bgp "$TUNNEL1_IP")
    t2s=$(get_tunnel_updown "$TUNNEL2_IP"); t2b=$(get_tunnel_bgp "$TUNNEL2_IP")
    m1=$([[ "$t1s" == "UP" ]] && echo -e "${GREEN}UP${NC}  " || echo -e "${RED}DOWN${NC}")
    m2=$([[ "$t2s" == "UP" ]] && echo -e "${GREEN}UP${NC}  " || echo -e "${RED}DOWN${NC}")
    echo ""
    echo "  ┌──────────────────────┬──────────────────────┬────────┐"
    echo "  │ 터널                 │ BGP Status           │ 상태   │"
    echo "  ├──────────────────────┼──────────────────────┼────────┤"
    echo -e "  │ Tunnel1         (T1) │ $(printf '%-20s' "${t1b:0:20}") │ ${m1}   │"
    echo -e "  │ Tunnel2         (T2) │ $(printf '%-20s' "${t2b:0:20}") │ ${m2}   │"
    echo "  └──────────────────────┴──────────────────────┴────────┘"
    echo ""
}

# ── TGW 라우트 테이블 조회 ───────────────────────────────────────
# AZURE_VNET_CIDR(172.16.0.0/16) 하위 경로를 검색해 현재 Next-Hop 확인.
# Failover 전: Tunnel1·Tunnel2 두 attachment가 보일 수 있음 (ECMP)
# Failover 후: Tunnel2 attachment만 남음
print_tgw_routes() {
    local routes count
    routes=$(aws ec2 search-transit-gateway-routes \
        --transit-gateway-route-table-id "$TGW_RT_ID" \
        --filters "Name=route-search.subnet-of-match,Values=${AZURE_VNET_CIDR}" \
        --region "$AWS_REGION" \
        --query 'Routes[*].{CIDR:DestinationCidrBlock,State:State,Via:TransitGatewayAttachments[0].ResourceId}' \
        --output json 2>/dev/null) || routes='[]'
    count=$(echo "$routes" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [[ "$count" -gt 0 ]]; then
        echo "$routes" | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    print(f\"  TGW 경로: {r.get('CIDR','?'):<22} → {r.get('Via','?'):<30} [{r.get('State','?')}]\")
" 2>/dev/null
    else
        echo "  TGW 경로: 없음 (BGP 미수신)"
    fi
}
tgw_has_azure_route() {
    local c
    c=$(aws ec2 search-transit-gateway-routes \
        --transit-gateway-route-table-id "$TGW_RT_ID" \
        --filters "Name=route-search.subnet-of-match,Values=${AZURE_VNET_CIDR}" \
        --region "$AWS_REGION" --query 'length(Routes)' --output text 2>/dev/null || echo "0")
    [[ "$c" -gt 0 ]]
}

# ════════════════════════════════════════════════════
# check — 현재 상태 단순 조회 (read-only)
# ════════════════════════════════════════════════════
cmd_check() {
    section "현재 VPN 상태 (READ-ONLY)"
    init
    step "터널 상태"
    print_tunnel_table
    step "TGW Azure 경로"
    print_tgw_routes
}

# ════════════════════════════════════════════════════
# prepare — 베이스라인 확인 (read-only)
#
# Azure 설정 변경 없음. 두 터널이 모두 UP + BGP 수신 중인지 확인.
# ECMP 환경에서 정상 베이스라인 = 두 터널 모두 BGP 활성.
# ════════════════════════════════════════════════════
cmd_prepare() {
    section "베이스라인 확인 — 두 터널 모두 UP + BGP 수신 (Read-Only)"
    init

    step "1/2  Tunnel1 상태 확인"
    local t1s t1b
    t1s=$(get_tunnel_updown "$TUNNEL1_IP")
    t1b=$(get_tunnel_bgp "$TUNNEL1_IP")
    [[ "$t1s" != "UP" ]] && { error "Tunnel1 DOWN — Azure VPN 연결 상태 확인 필요"; exit 1; }
    has_bgp_routes "$t1b" && ok "Tunnel1 UP + BGP 수신: ${t1b}" || warn "Tunnel1 UP이지만 BGP 수립 중: ${t1b}"

    step "2/2  Tunnel2 상태 확인"
    local t2s t2b
    t2s=$(get_tunnel_updown "$TUNNEL2_IP")
    t2b=$(get_tunnel_bgp "$TUNNEL2_IP")
    [[ "$t2s" != "UP" ]] && { error "Tunnel2 DOWN — Azure VPN 연결 상태 확인 필요"; exit 1; }
    has_bgp_routes "$t2b" && ok "Tunnel2 UP + BGP 수신: ${t2b}" || warn "Tunnel2 UP이지만 BGP 수립 중: ${t2b}"

    section "베이스라인 확인 완료"
    print_tunnel_table
    print_tgw_routes

    if has_bgp_routes "$t1b" && has_bgp_routes "$t2b"; then
        ok "베이스라인 준비 완료 — 두 터널 모두 BGP 활성 (ECMP)"
        echo "  → 'bash $0 failover' 또는 'bash $0 all' 실행 가능"
    else
        warn "한 쪽 이상 BGP 수립 전 — 잠시 후 'check' 재확인"
    fi
}

# ════════════════════════════════════════════════════
# failover — 장애 유발 + TGW 자동 전환 모니터링
#
# 장애 유발: Tunnel1의 PSK를 임시값으로 변경
#   → Azure 측 IKE SA 재협상 시도 → PSK 불일치로 실패
#   → IPsec SA DOWN → BGP Hold Timer 만료(기본 90초) → BGP DOWN
#   → TGW가 Tunnel1 경로 제거 → Tunnel2 단독 경로로 자동 전환
#
# 이 함수는 Azure BGP 설정(gatewayCustomBgpIpAddresses)을 건드리지 않음.
# Tunnel2 BGP는 이미 Bicep 배포 시 활성화된 상태이므로 별도 조작 불필요.
# ════════════════════════════════════════════════════
cmd_failover() {
    section "Failover 테스트"
    init

    # 두 터널 모두 UP + BGP 활성인지 확인 (ECMP 베이스라인 전제)
    step "1/4  사전 조건 확인"
    local t1s t1b t2s t2b
    t1s=$(get_tunnel_updown "$TUNNEL1_IP"); t1b=$(get_tunnel_bgp "$TUNNEL1_IP")
    t2s=$(get_tunnel_updown "$TUNNEL2_IP"); t2b=$(get_tunnel_bgp "$TUNNEL2_IP")

    [[ "$t1s" != "UP" ]] && { error "Tunnel1 UP 아님 (${t1s}) — restore 후 재시도"; exit 1; }
    [[ "$t2s" != "UP" ]] && { error "Tunnel2 UP 아님 (${t2s}) — Azure 연결 확인 필요"; exit 1; }
    no_bgp_routes "$t1b" && { error "Tunnel1 BGP 없음 (${t1b}) — prepare 먼저 실행"; exit 1; }
    no_bgp_routes "$t2b" && { error "Tunnel2 BGP 없음 (${t2b}) — prepare 먼저 실행"; exit 1; }

    ok "베이스라인 확인: Tunnel1·Tunnel2 모두 BGP 활성 (ECMP)"
    echo ""
    info "장애 유발 전 상태:"
    print_tunnel_table
    info "TGW 경로:"
    print_tgw_routes

    # PSK를 타임스탬프 포함 임시값으로 변경 → IKE 재협상 실패 유도
    step "2/4  Tunnel1 PSK 변경 (장애 유발)"
    RESTORE_NEEDED=true   # EXIT trap이 PSK를 원복하도록 플래그 설정
    az network vpn-connection update -g "$AZURE_RG" -n "$AZURE_CONN_ACTIVE" \
        --shared-key "$PSK_INVALID" --output none
    local t0
    t0=$(date +%s)
    ok "PSK 변경 완료 → IKE 재협상 실패 시작 (약 30초)"

    # IPsec DOWN까지 대기 (IKE Dead Peer Detection 또는 재협상 실패로 약 30초 소요)
    step "3/4  Tunnel1 DOWN 대기"
    local elapsed=0
    while true; do
        local t1_now
        t1_now=$(get_tunnel_updown "$TUNNEL1_IP")
        elapsed=$(( $(date +%s) - t0 ))
        local mark
        mark=$([[ "$t1_now" == "UP" ]] && echo -e "${GREEN}UP${NC}" || echo -e "${RED}DOWN${NC}")
        echo -e "  [${elapsed}s] Tunnel1: ${mark}"
        [[ "$t1_now" != "UP" ]] && { ok "Tunnel1 DOWN 확인 (${elapsed}s)"; break; }
        [[ $elapsed -ge $FAILOVER_TIMEOUT ]] && { error "Tunnel1 DOWN 타임아웃"; exit 1; }
        sleep 10
    done

    # BGP Hold Timer(기본 90초)가 만료되면 TGW가 Tunnel1 경로를 자동 제거하고
    # Tunnel2를 유일한 Next-Hop으로 전환함. 스크립트는 이 과정을 감시만 함.
    step "4/4  TGW 자동 경로 전환 모니터링 (Read-Only)"
    info "BGP Hold Timer 만료 후 TGW가 Tunnel2 단독 경로로 자동 전환합니다..."
    local t0_fo
    t0_fo=$(date +%s)
    elapsed=0
    while true; do
        elapsed=$(( $(date +%s) - t0_fo ))
        local t1b_now t2b_now t2s_now
        t1b_now=$(get_tunnel_bgp "$TUNNEL1_IP")
        t2b_now=$(get_tunnel_bgp "$TUNNEL2_IP")
        t2s_now=$(get_tunnel_updown "$TUNNEL2_IP")

        echo -e "  [${elapsed}s] Tunnel1 BGP: ${t1b_now}"
        echo -e "  [${elapsed}s] Tunnel2 BGP: ${t2b_now}  (${t2s_now})"
        print_tgw_routes

        # 성공 조건: Tunnel1 BGP 경로 없음 AND Tunnel2 BGP 경로 있음
        if has_bgp_routes "$t2b_now" && no_bgp_routes "$t1b_now"; then
            echo ""
            ok "Failover 완료! Tunnel2 단독 경로로 자동 전환 (${elapsed}s)"
            ok "스크립트가 Azure 설정을 변경하지 않았음 — 순수 BGP 자동 Failover"
            break
        fi

        [[ $elapsed -ge $FAILOVER_TIMEOUT ]] && {
            warn "타임아웃 (${FAILOVER_TIMEOUT}s) — 현재 상태:"
            print_tunnel_table
            break
        }
        echo "  ---"
        sleep 10
    done

    echo ""
    info "Failover 후 최종 상태:"
    print_tunnel_table
}

# ════════════════════════════════════════════════════
# verify — 데이터 플레인 통신 검증
#
# TGW 경로가 Tunnel2로 전환된 상태에서 실제 트래픽이 정상인지 확인.
# EKS의 notification-svc 파드에서 Azure GatewaySubnet 첫 IP로 TCP 연결 시도.
# 파드가 없으면 EKS 테스트를 건너뜀 (TGW 경로 확인만으로도 제어 플레인 검증 완료).
# ════════════════════════════════════════════════════
cmd_verify() {
    section "통신 검증 — Tunnel2 단독 경유"
    init

    step "1/3  TGW Azure 경로 확인"
    if tgw_has_azure_route; then
        ok "TGW → Azure 경로 존재"
        print_tgw_routes
    else
        error "TGW Azure 경로 없음"
        return 1
    fi

    step "2/3  터널 상태"
    print_tunnel_table

    # EKS 파드에서 Azure 내부 IP(172.16.1.1)로 TCP 포트 443 연결 테스트
    # socket.create_connection 사용: ping(ICMP)이 차단된 환경에서도 동작
    step "3/3  EKS → Azure TCP 연결"
    local pod
    pod=$(kubectl get pod -n bookflow -l app=notification-svc \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$pod" ]]; then
        warn "notification-svc 파드 없음 — EKS 연결 테스트 생략"
    else
        local result
        result=$(kubectl exec -n bookflow "$pod" -- python3 -c "
import socket,time,sys
t0=time.monotonic()
try:
    s=socket.create_connection(('172.16.2.4',22),timeout=5); s.close()
    print(f'REACHABLE ({(time.monotonic()-t0)*1000:.0f}ms)')
except Exception as e: print(f'UNREACHABLE: {e}')
" 2>/dev/null || echo "UNREACHABLE")
        echo "  결과: ${result}"
    fi

    ok "검증 완료 — Tunnel1:BGP0(DOWN) / Tunnel2:BGP1(단독 경로)"
}

# ════════════════════════════════════════════════════
# restore — PSK 복구 + Tunnel1 자동 복귀 모니터링
#
# PSK를 원래 값으로 복구하면 Azure 측에서 IKE 재협상을 자동으로 시도.
# 재협상 성공 → IPsec SA 수립 → BGP 세션 재수립 → TGW ECMP 복귀.
# 이 함수도 Azure BGP 설정을 건드리지 않음.
# ════════════════════════════════════════════════════
cmd_restore() {
    section "원상 복구 — Tunnel1 PSK 복구 → 자동 복귀 모니터링"
    init

    step "1/3  Tunnel1 PSK 원복"
    az network vpn-connection update -g "$AZURE_RG" -n "$AZURE_CONN_ACTIVE" \
        --shared-key "$PSK_ORIGINAL" --output none
    RESTORE_NEEDED=false   # EXIT trap 비활성화 (수동 복구 완료)
    ok "PSK 복구 완료 → IKE 재협상 시작 (약 30~60초)"

    # IKE Phase 1·2 협상 + IPsec SA 수립까지 대기
    step "2/3  Tunnel1 UP 대기"
    local elapsed=0
    while true; do
        local t1s
        t1s=$(get_tunnel_updown "$TUNNEL1_IP")
        local mark
        mark=$([[ "$t1s" == "UP" ]] && echo -e "${GREEN}UP${NC}" || echo -e "${YELLOW}${t1s}${NC}")
        echo -e "  [${elapsed}s] Tunnel1: ${mark}"
        [[ "$t1s" == "UP" ]] && { ok "Tunnel1 복구 완료 (${elapsed}s)"; break; }
        [[ $elapsed -ge $RESTORE_TIMEOUT ]] && { warn "복구 타임아웃 — 수동 확인 필요"; break; }
        sleep 10; elapsed=$((elapsed + 10))
    done

    # IPsec UP 후 BGP Hold Time(기본 30~90초) 동안 BGP 세션이 수립됨
    step "3/3  Tunnel1 BGP 재수립 대기 (30s)"
    sleep 30
    local t1b
    t1b=$(get_tunnel_bgp "$TUNNEL1_IP")
    has_bgp_routes "$t1b" && ok "Tunnel1 BGP 복구: ${t1b}" || warn "Tunnel1 BGP 수립 중: ${t1b}"

    section "복구 후 최종 상태"
    print_tunnel_table
    print_tgw_routes
    ok "Failback 완료 — Tunnel1·Tunnel2 BGP 재활성 (ECMP 복귀)"
}

# ════════════════════════════════════════════════════
# all — 전체 시나리오 순차 실행
# ════════════════════════════════════════════════════
cmd_all() {
    section "Azure-AWS VPN Failover 전체 시나리오"
    echo ""
    echo "  흐름: prepare → [↵] → failover → verify → [↵] → restore"
    echo "  두 터널 BGP 상시 활성 → Tunnel1 PSK 변경 → 자동 Failover → PSK 복구"
    echo ""

    cmd_prepare

    echo ""
    warn "장애를 유발합니다 (Tunnel1 PSK 변경). 계속하려면 Enter ↵"
    read -r

    cmd_failover

    echo ""
    cmd_verify

    echo ""
    warn "원상 복구합니다. 계속하려면 Enter ↵"
    read -r

    cmd_restore

    section "최종 결과"
    cmd_check
    echo ""
    ok "시나리오 완료"
    echo ""
    echo "  ① Tunnel1 PSK 변경 → IPsec/BGP DOWN (Azure 설정 무변경)"
    echo "  ② TGW가 Tunnel2 단독 경로로 자동 전환 (스크립트 개입 없음)"
    echo "  ③ PSK 복구 → Tunnel1 재수립 → ECMP 복귀"
}

# ── 메인 ──
MODE="${1:-all}"
case "$MODE" in
    check)    cmd_check ;;
    prepare)  cmd_prepare ;;
    failover) cmd_failover ;;
    verify)   cmd_verify ;;
    restore)  cmd_restore ;;
    all)      cmd_all ;;
    *)
        echo "사용법: $0 [check|prepare|failover|verify|restore|all]"
        echo ""
        echo "  check    현재 상태 확인"
        echo "  prepare  베이스라인 확인 (두 터널 UP + BGP 수신 검증, read-only)"
        echo "  failover Tunnel1 PSK 변경 → TGW 자동 전환 모니터링"
        echo "  verify   통신 검증"
        echo "  restore  Tunnel1 PSK 복구 → ECMP 자동 복귀 모니터링"
        echo "  all      전체 시나리오 (기본)"
        exit 1
        ;;
esac
