import { diagnosticSettingFullType } from 'br/public:avm/utl/types/avm-common-types:0.7.0'

// ------------------
//    TYPES
// ------------------

@description('Describes a private link origin configuration for Front Door.')
type privateLinkOriginType = {
  @description('Required. The resource ID of the private endpoint resource.')
  privateEndpointResourceId: string

  @description('Required. The location of the private endpoint resource.')
  privateEndpointLocation: string

  @description('Required. The resource type of the private link (e.g. "sites").')
  privateLinkResourceType: string
}

@description('Describes an origin for Front Door.')
type originType = {
  @description('Required. The hostname of the origin.')
  hostname: string

  @description('Required. Whether the origin is enabled.')
  enabledState: bool

  @description('Required. Private Link configuration for the origin.')
  privateLinkOrigin: privateLinkOriginType
}

// ------------------
//    PARAMETERS
// ------------------

@description('Required. Whether to enable deployment telemetry.')
param enableTelemetry bool

@description('Optional. Diagnostic Settings for the Front Door profile.')
param diagnosticSettings diagnosticSettingFullType[]?

@description('Required. Name of the AFD profile.')
param afdName string

@description('Required. Name of the endpoint under the profile, which is unique globally.')
param endpointName string

@description('Optional. State of the AFD endpoint.')
@allowed([
  'Enabled'
  'Disabled'
])
param endpointEnabled string = 'Enabled'

@description('Optional. Endpoint tags.')
param tags object = {}

@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
@description('Required. The pricing tier of the CDN profile.')
param skuName string

@description('Required. The name of the origin group.')
param originGroupName string

@description('Required. List of origins for the Front Door profile.')
param origins originType[]

@description('Optional. The action to take when a WAF rule is matched.')
@allowed([
  'Block'
  'Log'
  'Redirect'
])
param wafRuleSetAction string = 'Block'

@description('Optional. WAF policy enabled state.')
@allowed([
  'Enabled'
  'Disabled'
])
param wafPolicyState string = 'Enabled'

@description('Optional. WAF policy mode.')
@allowed([
  'Detection'
  'Prevention'
])
param wafPolicyMode string = 'Prevention'

module waf 'br/public:avm/res/network/front-door-web-application-firewall-policy:0.3.3' = {
  name: 'wafPolicy-${uniqueString(resourceGroup().id)}'
  params: {
    name: 'waffrontdoor'
    location: 'Global'
    enableTelemetry: enableTelemetry
    tags: tags
    sku: skuName
    policySettings: {
      enabledState: wafPolicyState
      mode: wafPolicyMode
      requestBodyCheck: 'Enabled'
    }
    customRules: {
      rules: [
        {
          name: 'BlockMethod'
          enabledState: 'Enabled'
          action: 'Block'
          ruleType: 'MatchRule'
          priority: 10
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 100
          matchConditions: [
            {
              matchVariable: 'RequestMethod'
              operator: 'Equal'
              negateCondition: true
              matchValue: [
                'GET'
                'OPTIONS'
                'HEAD'
              ]
            }
          ]
        }
      ]
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: wafRuleSetAction
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: wafRuleSetAction
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

module frontDoor 'br/public:avm/res/cdn/profile:0.17.1' = {
  name: 'frontDoorDeployment-${uniqueString(resourceGroup().id)}'
  params: {
    name: afdName
    sku: skuName
    location: 'global'
    enableTelemetry: enableTelemetry
    originResponseTimeoutSeconds: 120
    managedIdentities: {
      systemAssigned: true
    }
    diagnosticSettings: diagnosticSettings
    afdEndpoints: [
      {
        name: endpointName
        enabledState: endpointEnabled

        routes: [
          {
            name: '${originGroupName}-route'
            originGroupName: originGroupName
            patternsToMatch: [
              '/*'
            ]
            forwardingProtocol: 'HttpsOnly'
            linkToDefaultDomain: 'Enabled'
            httpsRedirect: 'Enabled'
            enabledState: 'Enabled'
          }
        ]
        tags: tags
      }
    ]
    originGroups: [
      {
        name: originGroupName
        loadBalancingSettings: {
          sampleSize: 4
          successfulSamplesRequired: 3
          additionalLatencyInMilliseconds: 50
        }
        healthProbeSettings: {
          probePath: '/'
          probeRequestType: 'GET'
          probeProtocol: 'Https'
          probeIntervalInSeconds: 100
        }
        sessionAffinityState: 'Disabled'
        trafficRestorationTimeToHealedOrNewEndpointsInMinutes: 10
        origins: [
          for (origin, index) in origins: {
            name: replace(origin.hostname, '.', '-')
            hostName: origin.hostname
            httpPort: 80
            httpsPort: 443
            priority: 1
            weight: 1000
            enabledState: origin.enabledState ? 'Enabled' : 'Disabled'
            enforceCertificateNameCheck: true
            sharedPrivateLinkResource: {
              privateLink: {
                id: origin.privateLinkOrigin.privateEndpointResourceId
              }
              privateLinkLocation: origin.privateLinkOrigin.privateEndpointLocation
              requestMessage: 'frontdoor'
              groupId: origin.privateLinkOrigin.privateLinkResourceType
            }
          }
        ]
      }
    ]
    securityPolicies: [
      {
        name: 'webApplicationFirewall'
        wafPolicyResourceId: waf.outputs.resourceId
        associations: [
          {
            // Note: resourceId() is necessary here because the AFD endpoint is created within
            // the same module call and cannot be referenced directly as a Bicep symbolic name.
            domains: [
              {
                id: resourceId(
                  subscription().subscriptionId,
                  resourceGroup().name,
                  'Microsoft.Cdn/profiles/afdEndpoints',
                  afdName,
                  endpointName
                )
              }
            ]
            patternsToMatch: [
              '/*'
            ]
          }
        ]
      }
    ]

    tags: tags
  }
}

@description('The name of the CDN profile.')
output afdProfileName string = frontDoor.outputs.name

@description('The resource ID of the CDN profile.')
output afdProfileResourceId string = frontDoor.outputs.resourceId

@description('Name of the endpoint.')
output endpointName string = frontDoor.outputs.?endpointName ?? ''

@description('HostName of the endpoint.')
output afdEndpointHostName string = frontDoor.outputs.?uri ?? ''

@description('The resource group where the CDN profile is deployed.')
output resourceGroupName string = resourceGroup().name

@description('The type of the CDN profile.')
output profileType string = frontDoor.outputs.profileType
