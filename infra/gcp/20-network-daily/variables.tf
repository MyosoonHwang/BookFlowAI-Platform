variable "aws_vpc_cidrs" {
  description = "AWS VPC CIDR ranges used for cross-cloud routing inputs."
  type        = list(string)
}

variable "aws_peer_ips" {
  description = "AWS VPN public peer IPs exposed for the four TGW tunnel endpoints."
  type        = list(string)
  default     = ["1.1.1.1", "2.2.2.2", "3.3.3.3", "4.4.4.4"]
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
  description = "Per-tunnel BGP settings."
  type = map(object({
    vpn_gateway_interface           = number
    peer_external_gateway_interface = number
    router_ip_cidr                  = string
    peer_ip_address                 = string
    advertised_route_priority       = optional(number, 100)
  }))
}

variable "psc_endpoint_ip" {
  description = "Internal IP used by the Private Service Connect endpoint for Google APIs."
  type        = string
}
