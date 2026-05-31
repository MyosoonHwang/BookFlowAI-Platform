// modules/vpn-connection.bicep
// AWS TGW ↔ Azure VPN — Active/Standby Dual Connection
//
// AWS VPN Connection 1개 = 터널 2개 (AWS가 자동으로 2개 outside IP 부여)
// Azure는 각 터널별로 별도 VPN Connection을 생성:
//   - conn-{prefix}-aws-active  : Tunnel1 (169.254.21.4/30)
//   - conn-{prefix}-aws-standby : Tunnel2 (169.254.21.8/30)
//
// APIPA BGP IP는 배포 시 gatewayCustomBgpIpAddresses로 정적 설정.
// 장애 테스트 중 Azure 설정을 수정하지 않는다. 장애 유발은 PSK 변경만 사용.

param prefix string
param vpnGatewayName string

// ── Active 터널 파라미터 (AWS Tunnel1) ─────────────────────────────
// AWS VPN Connection 의 첫 번째 tunnel outside public IP (e.g. 52.193.102.120)
param awsTgwActiveIp string
// AWS Tunnel1 inside CIDR 169.254.21.4/30 → VGW side BGP IP = 169.254.21.5
param awsTgwActiveBgpPeeringIp string

// ── Standby 터널 파라미터 (AWS Tunnel2) ────────────────────────────
// AWS VPN Connection 의 두 번째 tunnel outside public IP (e.g. 54.64.16.42)
param awsTgwStandbyIp string
// AWS Tunnel2 inside CIDR 169.254.21.8/30 → VGW side BGP IP = 169.254.21.9
param awsTgwStandbyBgpPeeringIp string

@secure()
param preSharedKey string

// ── APIPA BGP IP (Azure side, 배포 시 고정) ────────────────────────
// Active: 169.254.21.4/30 customer side = 169.254.21.6
// Standby: 169.254.21.8/30 customer side = 169.254.21.10
param azureActiveBgpIp string = '169.254.21.6'
param azureStandbyBgpIp string = '169.254.21.10'

// AWS 대역 (TGW BGP 로 광고되는 대역)
var awsCidrPrefixes = [
  '10.0.0.0/16'  // Egress VPC
  '10.1.0.0/16'  // BookFlow AI VPC
  '10.2.0.0/16'  // Data VPC
  '10.3.0.0/16'  // Sales Data VPC
]

var vpnGwIpconfigId = '${resourceId('Microsoft.Network/virtualNetworkGateways', 'vpngw-${prefix}')}/ipConfigurations/ipconfig-active'

var ipsecPolicy = {
  saLifeTimeSeconds: 27000
  saDataSizeKilobytes: 102400000
  ipsecEncryption: 'AES256'
  ipsecIntegrity: 'SHA256'
  ikeEncryption: 'AES256'
  ikeIntegrity: 'SHA256'
  dhGroup: 'DHGroup14'
  pfsGroup: 'PFS2048'
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-05-01' existing = {
  name: vpnGatewayName
}

// ── Active: Local Network Gateway (AWS Tunnel1 outside IP) ─────────
resource lngAwsActive 'Microsoft.Network/localNetworkGateways@2023-05-01' = {
  name: 'lng-${prefix}-aws-active'
  location: resourceGroup().location
  properties: {
    gatewayIpAddress: awsTgwActiveIp
    localNetworkAddressSpace: {
      addressPrefixes: awsCidrPrefixes
    }
    bgpSettings: {
      asn: 64512
      bgpPeeringAddress: awsTgwActiveBgpPeeringIp
    }
  }
}

// ── Active: VPN Connection ──────────────────────────────────────────
resource vpnConnActive 'Microsoft.Network/connections@2023-05-01' = {
  name: 'conn-${prefix}-aws-active'
  location: resourceGroup().location
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: {
      id: vpnGateway.id
      properties: {}
    }
    localNetworkGateway2: {
      id: lngAwsActive.id
      properties: {}
    }
    sharedKey: preSharedKey
    enableBgp: true
    // 장애 테스트 중 절대 수정 금지 — PSK 변경만으로 장애 유발
    gatewayCustomBgpIpAddresses: [
      {
        ipConfigurationId: vpnGwIpconfigId
        customBgpIpAddress: azureActiveBgpIp
      }
    ]
    ipsecPolicies: [ipsecPolicy]
  }
}

// ── Standby: Local Network Gateway (AWS Tunnel2 outside IP) ────────
resource lngAwsStandby 'Microsoft.Network/localNetworkGateways@2023-05-01' = {
  name: 'lng-${prefix}-aws-standby'
  location: resourceGroup().location
  properties: {
    gatewayIpAddress: awsTgwStandbyIp
    localNetworkAddressSpace: {
      addressPrefixes: awsCidrPrefixes
    }
    bgpSettings: {
      asn: 64512
      bgpPeeringAddress: awsTgwStandbyBgpPeeringIp
    }
  }
}

// ── Standby: VPN Connection ─────────────────────────────────────────
resource vpnConnStandby 'Microsoft.Network/connections@2023-05-01' = {
  name: 'conn-${prefix}-aws-standby'
  location: resourceGroup().location
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: {
      id: vpnGateway.id
      properties: {}
    }
    localNetworkGateway2: {
      id: lngAwsStandby.id
      properties: {}
    }
    sharedKey: preSharedKey
    enableBgp: true
    // 장애 테스트 중 절대 수정 금지
    gatewayCustomBgpIpAddresses: [
      {
        ipConfigurationId: vpnGwIpconfigId
        customBgpIpAddress: azureStandbyBgpIp
      }
    ]
    ipsecPolicies: [ipsecPolicy]
  }
}

// ── 출력값 ─────────────────────────────────────────────────────────
output activeConnectionId string = vpnConnActive.id
output activeConnectionName string = vpnConnActive.name
output standbyConnectionId string = vpnConnStandby.id
output standbyConnectionName string = vpnConnStandby.name
