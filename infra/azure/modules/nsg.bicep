// modules/nsg.bicep
// Services / Function 서브넷용 NSG

param location string
param prefix string

// AWS ping-test VPC CIDR — SSH 소스 제한에 사용
// vpc-ping-test.yaml의 VPC(10.100.0.0/24)에서만 SSH 허용
var awsPingTestCidr = '10.100.0.0/24'

// AWS 전체 VPC 대역 — ICMP 소스 범위
// TGW에 연결된 모든 AWS VPC(10.0.0.0/16, 10.1.0.0/16 등)에서 ping 허용
var awsVpcCidr = '10.0.0.0/8'

resource servicesNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-${prefix}-services'
  location: location
  properties: {
    securityRules: [
      {
        // ICMP(ping): AWS EC2(10.0.0.0/8)에서 이 서브넷 VM으로 ping 허용
        // protocol 'Icmp'는 포트 개념 없으므로 destinationPortRange = '*'
        name: 'allow-icmp-from-aws'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: awsVpcCidr
          destinationAddressPrefix: '*'
        }
      }
      {
        // SSH(22): ping-test EC2(10.100.0.0/24)에서만 허용
        // Azure VM에 SSH 접속해 반대 방향 ping(Azure → AWS) 테스트용
        name: 'allow-ssh-from-aws-ping-test'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: awsPingTestCidr
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'deny-internet-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource functionNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-${prefix}-function'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-https-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'deny-internet-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

output servicesNsgId string = servicesNsg.id
output functionNsgId string = functionNsg.id
