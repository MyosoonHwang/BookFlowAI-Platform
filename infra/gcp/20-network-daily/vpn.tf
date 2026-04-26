# WARNING:
# This HA VPN layer is a high-cost daily resource set for BOOKFLOW.
# Per the architecture rule, deploy only during 09:00-18:00 KST via start-day.sh
# and destroy after business hours via stop-day.sh.

resource "google_compute_ha_vpn_gateway" "bookflow_aws_ha_vpn" {
  name    = "bookflow-aws-ha-vpn"
  project = var.project_id
  region  = var.region
  network = data.google_compute_network.bookflow_vpc.id
}

resource "google_compute_external_vpn_gateway" "aws_tgw" {
  name            = "bookflow-aws-tgw-external-gw"
  project         = var.project_id
  redundancy_type = "FOUR_IPS_REDUNDANCY"

  dynamic "interface" {
    for_each = { for index, ip in var.aws_peer_ips : tostring(index) => ip }
    content {
      id         = tonumber(interface.key)
      ip_address = interface.value
    }
  }
}

resource "google_compute_vpn_tunnel" "aws_tunnels" {
  for_each = var.bgp_sessions

  name                            = "bookflow-aws-tunnel-${each.key}"
  project                         = var.project_id
  region                          = var.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.bookflow_aws_ha_vpn.id
  vpn_gateway_interface           = each.value.vpn_gateway_interface
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_tgw.id
  peer_external_gateway_interface = each.value.peer_external_gateway_interface
  router                          = google_compute_router.bookflow_aws_router.id
  shared_secret                   = var.vpn_shared_secret

  depends_on = [
    google_compute_router.bookflow_aws_router,
    google_compute_ha_vpn_gateway.bookflow_aws_ha_vpn,
    google_compute_external_vpn_gateway.aws_tgw,
  ]
}

resource "google_compute_router_interface" "aws_interfaces" {
  for_each = var.bgp_sessions

  name       = "bookflow-aws-if-${each.key}"
  project    = var.project_id
  region     = var.region
  router     = google_compute_router.bookflow_aws_router.name
  ip_range   = each.value.router_ip_cidr
  vpn_tunnel = google_compute_vpn_tunnel.aws_tunnels[each.key].name
}

resource "google_compute_router_peer" "aws_peers" {
  for_each = var.bgp_sessions

  name                      = "bookflow-aws-bgp-${each.key}"
  project                   = var.project_id
  region                    = var.region
  router                    = google_compute_router.bookflow_aws_router.name
  interface                 = google_compute_router_interface.aws_interfaces[each.key].name
  peer_ip_address           = each.value.peer_ip_address
  peer_asn                  = var.aws_tgw_bgp_asn
  advertised_route_priority = each.value.advertised_route_priority
}

locals {
  default_bgp_sessions = {
    "0" = {
      vpn_gateway_interface           = 0
      peer_external_gateway_interface = 0
      router_ip_cidr                  = "169.254.21.1/30"
      peer_ip_address                 = "169.254.21.2"
      advertised_route_priority       = 100
    }
    "1" = {
      vpn_gateway_interface           = 0
      peer_external_gateway_interface = 1
      router_ip_cidr                  = "169.254.22.1/30"
      peer_ip_address                 = "169.254.22.2"
      advertised_route_priority       = 110
    }
    "2" = {
      vpn_gateway_interface           = 1
      peer_external_gateway_interface = 2
      router_ip_cidr                  = "169.254.23.1/30"
      peer_ip_address                 = "169.254.23.2"
      advertised_route_priority       = 100
    }
    "3" = {
      vpn_gateway_interface           = 1
      peer_external_gateway_interface = 3
      router_ip_cidr                  = "169.254.24.1/30"
      peer_ip_address                 = "169.254.24.2"
      advertised_route_priority       = 110
    }
  }
}
