import { diagnosticSettingFullType } from 'br/public:avm/utl/types/avm-common-types:0.7.0'

// NOTE: The resourceId() calls in this file are necessary for Application Gateway sub-resource
// self-references during creation, where symbolic names cannot be used.

@description('Required. Whether to enable deployment telemetry.')
param enableTelemetry bool

@description('Required. Name of the Application Gateway.')
param appGwName string

@description('Required. The resource ID of the subnet for the Application Gateway.')
param subnetResourceId string

@description('Required. The hostname of the web app backend.')
param backendHostName string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Tags for all resources.')
param tags object = {}

@description('Optional. The SKU of the Application Gateway.')
@allowed([
  'Standard_v2'
  'WAF_v2'
])
param skuName string = 'WAF_v2'

@description('Optional. The capacity (instance count) of the Application Gateway.')
param capacity int = 2

@description('Optional. Minimum autoscale capacity. Set to -1 to disable autoscale.')
param autoscaleMinCapacity int = 2

@description('Optional. Maximum autoscale capacity. Set to -1 to disable autoscale.')
param autoscaleMaxCapacity int = 10

@description('Optional. The health probe path.')
param healthProbePath string = '/healthz'

@description('Optional. Diagnostic Settings for the Application Gateway.')
param diagnosticSettings diagnosticSettingFullType[]?

@description('Optional. The availability zones for the Application Gateway.')
param availabilityZones int[] = [1, 2, 3]

@description('Optional. WAF policy mode. Only used when skuName is WAF_v2.')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

// ======================== //
// Variables                //
// ======================== //

var appGwPublicIpName = 'pip-${appGwName}'
var backendPoolName = 'backendPool'
var backendHttpSettingsName = 'backendHttpSettings'
var frontendPortHttpName = 'frontendPort-http'
var frontendPortHttpsName = 'frontendPort-https'
var httpListenerName = 'httpListener'
var requestRoutingRuleName = 'routingRule'
var healthProbeName = 'healthProbe'
var frontendIpConfigName = 'appGwPublicFrontendIp'
var gatewayIpConfigName = 'appGwIpConfig'

var isWaf = skuName == 'WAF_v2'

// ============ //
// Dependencies //
// ============ //

module publicIp 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  name: '${uniqueString(deployment().name, location)}-appgw-pip'
  params: {
    name: appGwPublicIpName
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    availabilityZones: availabilityZones
  }
}

module wafPolicy 'br/public:avm/res/network/application-gateway-web-application-firewall-policy:0.2.1' = if (isWaf) {
  name: '${uniqueString(deployment().name, location)}-appgw-waf'
  params: {
    name: 'waf-${appGwName}'
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
    }
    policySettings: {
      mode: wafMode
      state: 'Enabled'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
  }
}

module applicationGateway 'br/public:avm/res/network/application-gateway:0.8.0' = {
  name: '${uniqueString(deployment().name, location)}-appgw'
  params: {
    name: appGwName
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    sku: skuName
    capacity: capacity
    autoscaleMinCapacity: autoscaleMinCapacity
    autoscaleMaxCapacity: autoscaleMaxCapacity
    enableHttp2: true
    availabilityZones: availabilityZones
    diagnosticSettings: diagnosticSettings
    firewallPolicyResourceId: wafPolicy.?outputs.?resourceId
    gatewayIPConfigurations: [
      {
        name: gatewayIpConfigName
        properties: {
          subnet: {
            id: subnetResourceId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: frontendIpConfigName
        properties: {
          publicIPAddress: {
            id: publicIp.outputs.resourceId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: frontendPortHttpName
        properties: {
          port: 80
        }
      }
      {
        name: frontendPortHttpsName
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
        properties: {
          backendAddresses: [
            {
              fqdn: backendHostName
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: backendHttpSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 120
          probe: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/probes',
              appGwName,
              healthProbeName
            )
          }
        }
      }
    ]
    probes: [
      {
        name: healthProbeName
        properties: {
          protocol: 'Https'
          path: healthProbePath
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    httpListeners: [
      {
        name: httpListenerName
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              appGwName,
              frontendIpConfigName
            )
          }
          frontendPort: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendPorts',
              appGwName,
              frontendPortHttpName
            )
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: requestRoutingRuleName
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              appGwName,
              httpListenerName
            )
          }
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              appGwName,
              backendPoolName
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              appGwName,
              backendHttpSettingsName
            )
          }
        }
      }
    ]
  }
}

// ======================== //
// Outputs                  //
// ======================== //

@description('The name of the Application Gateway.')
output appGwName string = applicationGateway.outputs.name

@description('The resource ID of the Application Gateway.')
output appGwResourceId string = applicationGateway.outputs.resourceId

@description('The public IP address of the Application Gateway.')
output appGwPublicIpAddress string = publicIp.outputs.ipAddress

@description('The resource group the Application Gateway was deployed into.')
output resourceGroupName string = resourceGroup().name
