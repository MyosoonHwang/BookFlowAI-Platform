// modules/vnet.bicep
// VNet 과 서브넷 4개 (GatewaySubnet 에는 NSG 연결 안 함)

param location string
param prefix string
param vnetAddressPrefix string
param gatewaySubnetPrefix string
param servicesSubnetPrefix string
param functionSubnetPrefix string
param servicesNsgId string
param functionNsgId string

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-${prefix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [

      // VPN Gateway 용 — NSG 연결 금지
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }

      // 일반 서비스용
      {
        name: 'snet-services'
        properties: {
          addressPrefix: servicesSubnetPrefix
          networkSecurityGroup: {
            id: servicesNsgId
          }
        }
      }

      // Function App 용 (VNet Integration 위임 포함)
      {
        name: 'snet-function'
        properties: {
          addressPrefix: functionSubnetPrefix
          networkSecurityGroup: {
            id: functionNsgId
          }
          delegations: [
            {
              name: 'delegation-function'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

// ── 출력값 ───────────────────────────────────────────────
output vnetId string = vnet.id
output vnetName string = vnet.name

output gatewaySubnetId string = vnet.properties.subnets[0].id
output servicesSubnetId string = vnet.properties.subnets[1].id
output functionSubnetId string = vnet.properties.subnets[2].id
