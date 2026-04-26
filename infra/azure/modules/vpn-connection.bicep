// modules/vpn-connection.bicep
// AWS TGW 구축 완료 후 별도로 배포하는 파일
// 3일 구축 기간에는 배포하지 않음

param prefix string
param vpnGatewayName string

// AWS 팀에게 받아야 하는 값
param awsTgwActiveIp string
param awsTgwBgpPeeringIp string
param preSharedKey string

// AWS 대역 (TGW 라우팅 테이블에서 광고하는 대역)
var awsCidrPrefixes = [
  '10.0.0.0/16'  // Egress VPC
  '10.1.0.0/16'  // BookFlow AI VPC
  '10.2.0.0/16'  // Data VPC
  '10.3.0.0/16'  // Sales Data VPC
]

// 기존 VPN Gateway 참조
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-05-01' existing = {
  name: vpnGatewayName
}

// ── 로컬 네트워크 게이트웨이 (AWS TGW Active) ─────────────
resource lngAwsActive 'Microsoft.Network/localNetworkGateways@2023-05-01' = {
  name: 'lng-${prefix}-aws-active'
  location: resourceGroup().location
  properties: {
    gatewayIpAddress: awsTgwActiveIp
    localNetworkAddressSpace: {
      addressPrefixes: awsCidrPrefixes
    }
    bgpSettings: {
      asn: 64512  // AWS TGW BGP ASN
      bgpPeeringAddress: awsTgwBgpPeeringIp
    }
  }
}

// ── VPN Connection ────────────────────────────────────────
resource vpnConnection 'Microsoft.Network/connections@2023-05-01' = {
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
    ipsecPolicies: [
      {
        saLifeTimeSeconds: 27000
        saDataSizeKilobytes: 102400000
        ipsecEncryption: 'AES256'
        ipsecIntegrity: 'SHA256'
        ikeEncryption: 'AES256'
        ikeIntegrity: 'SHA256'
        dhGroup: 'DHGroup14'
        pfsGroup: 'PFS2048'
      }
    ]
  }
}

// ── 출력값 ───────────────────────────────────────────────
output connectionId string = vpnConnection.id
output connectionName string = vpnConnection.name
