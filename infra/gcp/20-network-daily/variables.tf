variable "aws_vpc_cidrs" {
  description = "AWS VPC CIDR ranges used for cross-cloud routing inputs."
  type        = list(string)
}

variable "aws_vpn_gateway_interfaces" {
  description = "AWS VPN public IPs exposed for the four TGW tunnel endpoints."
  type = map(object({
    ip_address = string
  }))
}

variable "aws_tgw_bgp_asn" {
  description = "Private ASN used by the AWS Transit Gateway / VPN attachment."
  type        = number
}

variable "vpn_shared_secrets" {
  description = "Pre-shared keys for the four HA VPN tunnels."
  type        = map(string)
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
