"""task-forecast · GCP HA VPN (forecast-svc Pod → Vertex AI Endpoint)."""
import os

from ..lib import Stack, log


def deploy() -> None:
    log.step("=== task-forecast · GCP HA VPN ===")
    if not Stack(tier="10", name="customer-gateway", template="").exists():
        log.err("customer-gateway 미배포 · base-up 먼저"); raise SystemExit(1)

    Stack(tier="60", name="tgw",
          template="60-network-cross-cloud/tgw.yaml").deploy()

    gcp_ip = os.environ.get("BOOKFLOW_GCP_VPN_GW_IP", "").strip()
    gcp_psk = os.environ.get("BOOKFLOW_GCP_VPN_PSK", "").strip()
    if gcp_ip and gcp_ip != "0.0.0.0":
        Stack(tier="10", name="customer-gateway",
              template="10-network-core/customer-gateway.yaml",
              parameters={"GcpHaVpnIp": gcp_ip}).deploy()
        params = {"EnableGcpVpn": "true"}
        if gcp_psk:
            params["GcpPresharedKey"] = gcp_psk
        Stack(tier="60", name="vpn-site-to-site",
              template="60-network-cross-cloud/vpn-site-to-site.yaml",
              parameters=params).deploy()
    else:
        log.warn("BOOKFLOW_GCP_VPN_GW_IP 환경변수 없음 · GCP VPN skip")
        log.info('  $env:BOOKFLOW_GCP_VPN_GW_IP = "우혁에게 받은 GCP HA VPN IP"')

    log.step("=== task-forecast 완료 ===")


def destroy() -> None:
    log.step("=== task-forecast-down ===")
    Stack(tier="60", name="vpn-site-to-site", template="").destroy()
    log.info("TGW 는 task-auth-pod 와 공유 · 유지 (필요 시 task-auth-pod-down 으로 정리)")
    log.step("=== task-forecast-down 완료 ===")
