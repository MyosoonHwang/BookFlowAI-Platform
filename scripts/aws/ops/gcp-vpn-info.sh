#!/usr/bin/env bash
# gcp-vpn-info.sh · AWS TGW → GCP HA VPN 연결 정보 추출 + terraform 자동 적용
#
# Usage:
#   bash scripts/aws/ops/gcp-vpn-info.sh          # 터널 1개 (기본, 비용 절감)
#   bash scripts/aws/ops/gcp-vpn-info.sh --full    # 터널 2개 (최종 테스트용)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
pre_flight

# ── 인수 파싱 ──
FULL_TUNNELS=false
for arg in "$@"; do
  case $arg in
    --full) FULL_TUNNELS=true ;;
  esac
done
export FULL_TUNNELS

echo ""
echo "════════════════════════════════════════════════════════"
echo "  AWS → GCP VPN 연결 정보 추출"
if [ "$FULL_TUNNELS" = "true" ]; then
  echo "  모드: 터널 2개 (--full)"
else
  echo "  모드: 터널 1개 (기본, 비용 절감)"
fi
echo "════════════════════════════════════════════════════════"

VPN_CONN_ID=$(aws cloudformation describe-stacks \
  --stack-name bookflow-60-vpn-site-to-site \
  --query "Stacks[0].Outputs[?OutputKey=='GcpVpnConnectionId'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [ -z "$VPN_CONN_ID" ] || [ "$VPN_CONN_ID" = "None" ]; then
  echo "  [ERROR] bookflow-60-vpn-site-to-site 스택이 없거나 GCP VPN 비활성화 상태"
  echo "  먼저 실행: BOOKFLOW_GCP_VPN_GW_IP=<IP> bash scripts/aws/ops/network-mode.sh tgw"
  exit 1
fi
echo ""
echo "  VPN Connection ID : $VPN_CONN_ID"

TGW_ASN=$(aws cloudformation describe-stacks \
  --stack-name bookflow-60-tgw \
  --query "Stacks[0].Outputs[?OutputKey=='TgwAsn'].OutputValue" \
  --output text 2>/dev/null || echo "64512")

# ── AWS VPN 정보 파싱 + terraform.tfvars 생성 ──
export SCRIPT_DIR
py - <<PYEOF
import boto3, os, sys, ipaddress, pathlib
sys.stdout.reconfigure(encoding='utf-8', line_buffering=True)

session  = boto3.Session(profile_name=os.environ['AWS_PROFILE'], region_name=os.environ['AWS_REGION'])
ec2      = session.client('ec2')

vpn = ec2.describe_vpn_connections(
    VpnConnectionIds=['$VPN_CONN_ID']
)['VpnConnections'][0]

telemetry = vpn.get('VgwTelemetry', [])
options   = vpn.get('Options', {}).get('TunnelOptions', [])

tunnels = []
for i, opt in enumerate(options[:2]):
    outside_ip   = telemetry[i]['OutsideIpAddress'] if i < len(telemetry) else '?'
    inside_cidr  = opt.get('TunnelInsideCidr', '')
    if inside_cidr:
        net      = ipaddress.ip_network(inside_cidr, strict=False)
        hosts    = list(net.hosts())
        aws_ip   = str(hosts[0])
        gcp_ip   = str(hosts[1])
        gcp_cidr = f'{gcp_ip}/{net.prefixlen}'
    else:
        aws_ip = gcp_ip = gcp_cidr = '?'
    tunnels.append({
        'idx': i, 'outside_ip': outside_ip, 'inside_cidr': inside_cidr,
        'aws_ip': aws_ip, 'gcp_ip': gcp_ip, 'gcp_cidr': gcp_cidr,
    })
    print(f'  Tunnel {i} Outside IP  : {outside_ip}')
    print(f'  Tunnel {i} Inside CIDR : {inside_cidr}  (AWS={aws_ip}  GCP={gcp_ip})')

tunnel_opts = vpn.get('Options', {}).get('TunnelOptions', [])
psk0 = tunnel_opts[0].get('PreSharedKey', '<PSK_HERE>') if len(tunnel_opts) > 0 else '<PSK_HERE>'
psk1 = tunnel_opts[1].get('PreSharedKey', psk0)         if len(tunnel_opts) > 1 else psk0
if psk0 != psk1:
    print(f'\n  PSK tunnel0 : {psk0}')
    print(f'  PSK tunnel1 : {psk1}')
else:
    print(f'\n  PSK : {psk0}')

vpcs  = ec2.describe_vpcs(Filters=[{'Name': 'tag:Name', 'Values': ['bookflow-*']}])['Vpcs']
cidrs = sorted(v['CidrBlock'] for v in vpcs)
print(f'\n  AWS VPC CIDRs : {cidrs}')

cidr_tf = '[' + ', '.join(f'"{c}"' for c in cidrs) + ']'
t0, t1  = tunnels[0], tunnels[1]
full    = os.environ.get('FULL_TUNNELS', 'false') == 'true'

# tunnel1은 --full 모드에서만 포함
tunnel1_hcl = f"""
  tunnel1 = {{
    vpn_gateway_interface           = 0
    peer_external_gateway_interface = 1
    shared_secret                   = "{psk1}"
    router_ip_cidr                  = "{t1['gcp_cidr']}"
    peer_ip_address                 = "{t1['aws_ip']}"
    advertised_route_priority       = 100
  }}""" if full else ""

tfvars_content = f"""project_id        = "project-8ab6bf05-54d2-4f5d-b8d"
vpc_name          = "bookflow-vpc"

aws_peer_ips      = ["{t0['outside_ip']}", "{t1['outside_ip']}"]
aws_tgw_bgp_asn   = $TGW_ASN
gcp_router_asn    = 64514

vpn_shared_secret = "{psk0}"

aws_vpc_cidrs     = {cidr_tf}
azure_vnet_cidr   = "10.1.0.0/16"
gcp_routed_cidr   = "10.50.0.0/24"
psc_endpoint_host_offset = 10

bgp_sessions = {{
  tunnel0 = {{
    vpn_gateway_interface           = 0
    peer_external_gateway_interface = 0
    shared_secret                   = "{psk0}"
    router_ip_cidr                  = "{t0['gcp_cidr']}"
    peer_ip_address                 = "{t0['aws_ip']}"
    advertised_route_priority       = 100
  }}{tunnel1_hcl}
}}
"""

script_dir  = pathlib.Path(os.environ.get('SCRIPT_DIR', '.')).resolve()
tfvars_path = script_dir.parents[2] / 'infra' / 'gcp' / '20-network-daily' / 'terraform.tfvars'
tfvars_path.write_text(tfvars_content, encoding='utf-8')
print(f'\n  → terraform.tfvars 저장 완료: {tfvars_path}')
PYEOF

# ════════════════════════════════════════════════════════
#  GCP Terraform 자동 적용
# ════════════════════════════════════════════════════════
GCP_PROJECT_ID="${GCP_PROJECT_ID:-project-8ab6bf05-54d2-4f5d-b8d}"
GCP_TF_DIR="$(realpath "$SCRIPT_DIR/../../../infra/gcp/20-network-daily")"
RGN="asia-northeast1"
PROJ_ID="$GCP_PROJECT_ID"
PRJ="projects/$GCP_PROJECT_ID"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  GCP Terraform 적용"
echo "════════════════════════════════════════════════════════"

# GCP 인증 (application-default 차단된 환경에서는 gcloud 토큰 사용)
GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
if [ -z "$GOOGLE_OAUTH_ACCESS_TOKEN" ]; then
  echo "  [ERROR] gcloud 인증 실패. gcloud auth login 실행 후 재시도"
  exit 1
fi
export GOOGLE_OAUTH_ACCESS_TOKEN

# terraform PATH (Windows: ~/bin에 설치된 경우)
export PATH="$PATH:$HOME/bin"

cd "$GCP_TF_DIR"

# init (.terraform 없으면 실행)
if [ ! -d ".terraform" ]; then
  echo "  terraform init..."
  terraform init -upgrade
fi

# idempotent import: state에 없고 GCP에 존재하면 import, 없으면 apply에서 생성
tf_import() {
  local addr="$1" id="$2"
  if terraform state show "$addr" &>/dev/null; then
    echo "  [SKIP]   $addr"
    return
  fi
  echo "  [IMPORT] $addr"
  terraform import "$addr" "$id" 2>/dev/null \
    || echo "  [CREATE] $addr (GCP에 없음 → apply 시 생성)"
}

echo ""
echo "  기존 GCP 리소스 확인 및 state 동기화..."
tf_import google_project_service.dns                               "$PROJ_ID/dns.googleapis.com"
tf_import google_compute_ha_vpn_gateway.bookflow_aws_ha_vpn        "$PRJ/regions/$RGN/vpnGateways/bookflow-aws-ha-vpn"
tf_import google_compute_external_vpn_gateway.aws_tgw              "$PRJ/global/externalVpnGateways/bookflow-aws-tgw-external-gw"
tf_import google_compute_router.bookflow_aws_router                "$PRJ/regions/$RGN/routers/bookflow-aws-cr"
tf_import google_compute_firewall.cross_cloud_ingress_private_api  "$PRJ/global/firewalls/bookflow-allow-cross-cloud-private-api"
tf_import google_compute_firewall.cross_cloud_ingress_deny_all     "$PRJ/global/firewalls/bookflow-deny-cross-cloud-ingress"
tf_import google_compute_firewall.cross_cloud_egress_private_api   "$PRJ/global/firewalls/bookflow-allow-cross-cloud-egress"
tf_import google_compute_firewall.cross_cloud_egress_deny_all      "$PRJ/global/firewalls/bookflow-deny-cross-cloud-egress"
tf_import google_compute_global_address.psc_googleapis_ip          "$PRJ/global/addresses/bookflow-psc-googleapis-ip"
tf_import google_compute_global_forwarding_rule.psc_googleapis     "$PRJ/global/forwardingRules/bookflowpscapi"
tf_import google_dns_managed_zone.googleapis_private               "$PRJ/managedZones/bookflow-googleapis-private"
tf_import google_dns_record_set.private_googleapis                 "$PRJ/managedZones/bookflow-googleapis-private/rrsets/private.googleapis.com./A"
tf_import google_dns_record_set.wildcard_private_googleapis        "$PRJ/managedZones/bookflow-googleapis-private/rrsets/*.private.googleapis.com./A"
tf_import google_dns_record_set.bigquery_googleapis                "$PRJ/managedZones/bookflow-googleapis-private/rrsets/bigquery.googleapis.com./A"

# for_each 리소스: bash 필수 (PowerShell은 따옴표 제거로 실패)
tf_import 'google_compute_vpn_tunnel.aws_tunnels["tunnel0"]'          "$PRJ/regions/$RGN/vpnTunnels/bookflow-aws-tunnel-tunnel0"
tf_import 'google_compute_router_interface.aws_interfaces["tunnel0"]' "$PROJ_ID/$RGN/bookflow-aws-cr/bookflow-aws-if-tunnel0"
tf_import 'google_compute_router_peer.aws_peers["tunnel0"]'           "$PROJ_ID/$RGN/bookflow-aws-cr/bookflow-aws-bgp-tunnel0"

if [ "$FULL_TUNNELS" = "true" ]; then
  tf_import 'google_compute_vpn_tunnel.aws_tunnels["tunnel1"]'          "$PRJ/regions/$RGN/vpnTunnels/bookflow-aws-tunnel-tunnel1"
  tf_import 'google_compute_router_interface.aws_interfaces["tunnel1"]' "$PROJ_ID/$RGN/bookflow-aws-cr/bookflow-aws-if-tunnel1"
  tf_import 'google_compute_router_peer.aws_peers["tunnel1"]'           "$PROJ_ID/$RGN/bookflow-aws-cr/bookflow-aws-bgp-tunnel1"
fi

echo ""
echo "  terraform apply..."
terraform apply -auto-approve

echo ""
echo "════════════════════════════════════════════════════════"
echo "  GCP VPN 터널 상태"
echo "════════════════════════════════════════════════════════"
gcloud compute vpn-tunnels list \
  --project="$GCP_PROJECT_ID" \
  --format="table(name,status,detailedStatus)" 2>/dev/null || true

echo ""
echo "  완료. AWS 터널 상태 확인:"
echo "  aws ec2 describe-vpn-connections \\"
echo "    --filters 'Name=tag:Name,Values=bookflow-vpn-gcp' \\"
echo "    --query 'VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status}' \\"
echo "    --output table --profile \$AWS_PROFILE --region \$AWS_REGION"
