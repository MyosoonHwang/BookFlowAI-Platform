variable "aws_vpc_cidrs" {
  description = "AWS VPC CIDR ranges used for cross-cloud routing inputs."
  type        = list(string)
}

variable "aws_peer_ips" {
  description = "AWS VPN public peer IPs exposed for the two TGW tunnel endpoints."
  type        = list(string)
  default     = ["1.1.1.1", "2.2.2.2"]

  validation {
    condition     = length(var.aws_peer_ips) == 2
    error_message = "aws_peer_ips must contain exactly two AWS TGW VPN outside public IPs for TWO_IPS_REDUNDANCY."
  }
}

variable "aws_tgw_bgp_asn" {
  description = "Private ASN used by the AWS Transit Gateway / VPN attachment."
  type        = number
}

variable "vpn_shared_secret" {
  description = "Pre-shared key reused by the HA VPN tunnels for local collaboration only."
  type        = string
  default     = "dummy-shared-secret-change-me"
  sensitive   = true
}

variable "bgp_sessions" {
  description = "Per-tunnel BGP settings for the two HA VPN tunnels."
  type = map(object({
    vpn_gateway_interface           = number
    peer_external_gateway_interface = number
    router_ip_cidr                  = string
    peer_ip_address                 = string
    advertised_route_priority       = optional(number, 100)
  }))

  validation {
    condition = (
      length(var.bgp_sessions) == 2 &&
      alltrue([
        for session in values(var.bgp_sessions) :
        contains([0, 1], session.vpn_gateway_interface) &&
        contains([0, 1], session.peer_external_gateway_interface)
      ])
    )
    error_message = "bgp_sessions must define exactly two tunnels using GCP HA VPN interfaces 0/1 and AWS external gateway interfaces 0/1."
  }
}

variable "psc_endpoint_ip" {
  description = "Internal IP used by the Private Service Connect endpoint for Google APIs."
  type        = string
}
