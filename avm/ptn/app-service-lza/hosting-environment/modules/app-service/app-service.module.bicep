import {
  diagnosticSettingFullType
  diagnosticSettingMetricsOnlyType
  diagnosticSettingLogsOnlyType
} from 'br/public:avm/utl/types/avm-common-types:0.7.0'

import {
  virtualNetworkLinkType
  siteConfigType
} from '../shared.types.bicep'

@description('Required. Whether to enable deployment telemetry.')
param enableTelemetry bool

@description('Optional, default is false. Set to true if you want to deploy ASE v3 instead of Multitenant App Service Plan.')
param deployAseV3 bool = false

@description('Optional if deployAseV3 = false. The identifier for the App Service Environment v3 resource.')
@minLength(1)
@maxLength(36)
param aseName string

@description('Required. Name of the App Service Plan.')
@minLength(1)
@maxLength(40)
param appServicePlanName string

@description('Required. Name of the web app.')
@maxLength(60)
param webAppName string

@description('Required. Name of the managed Identity that will be assigned to the web app.')
@minLength(3)
@maxLength(128)
param managedIdentityName string

// ======================== //
// Bring-Your-Own-Service   //
// ======================== //

@description('Optional. The resource ID of an existing App Service Plan. If provided, the module will skip creating a new plan and deploy the web app on the existing one.')
param existingAppServicePlanId string = ''

// ======================== //
// SKU & Scaling            //
// ======================== //

// See https://learn.microsoft.com/azure/app-service/overview-hosting-plans for available SKUs and tiers.
@description('Optional. The name of the SKU for the App Service Plan. Determines the tier, size, family and capacity. EP* SKUs are only for Azure Functions elastic premium plans.')
@metadata({
  example: '''
  // Premium v3
  'P0v3'
  'P1v3'
  'P2v3'
  'P3v3'
  // Premium v4
  'P0v4'
  'P1v4'
  'P2v4'
  'P3v4'
  // Premium Memory Optimized v3
  'P1mv3'
  'P2mv3'
  'P3mv3'
  'P4mv3'
  'P5mv3'
  // Premium Memory Optimized v4
  'P1mv4'
  'P3mv4'
  'P4mv4'
  'P5mv4'
  // Isolated v2
  'I1v2'
  'I2v2'
  'I3v2'
  'I4v2'
  'I5v2'
  'I6v2'
  // Functions Elastic Premium
  'EP1'
  'EP2'
  'EP3'
  '''
})
param sku resourceInput<'Microsoft.Web/serverfarms@2024-04-01'>.sku.name

@description('Optional. Set to true if you want to deploy the App Service Plan in a zone redundant manner. Default is true.')
param zoneRedundant bool = true

@description('Optional. Location for all resources.')
param location string

@description('Optional. Resource tags that we might need to add to all resources.')
param tags object

@description('Optional. Default is empty. If empty no Private Endpoint will be created for the resource. Otherwise, the subnet where the private endpoint will be attached to.')
param subnetPrivateEndpointResourceId string = ''

@description('Optional. Array of custom objects describing vNet links of the DNS zone. Each object should contain vnetName, vnetId, registrationEnabled.')
param virtualNetworkLinks virtualNetworkLinkType[] = []

@description('Required. Kind of server OS of the App Service Plan.')
@allowed(['windows', 'linux'])
param webAppBaseOs string

@description('Required. An existing Log Analytics workspace resource ID for creating App Insights and diagnostics.')
param logAnalyticsWorkspaceResourceId string

@description('Required. The subnet ID that is dedicated to the Web Server for VNet injection. If deployAseV3=true then this is the subnet dedicated to the ASE v3.')
param subnetIdForVnetInjection string

@description('Optional. If true, apps assigned to this App Service plan can be scaled independently. If false, apps assigned to this App Service plan will scale to all instances of the plan.')
param perSiteScaling bool = false

@description('Optional, default is 20. Maximum number of total workers allowed for this ElasticScaleEnabled App Service Plan.')
param maximumElasticWorkerCount int = 20

@description('Optional. Scaling worker count.')
param targetWorkerCount int = 0

@description('Optional. The instance size of the hosting plan (small, medium, or large).')
@allowed([
  0
  1
  2
])
param targetWorkerSize int = 0

@description('Optional. The site configuration for the web app.')
param siteConfig siteConfigType = {
  alwaysOn: true
  ftpsState: 'FtpsOnly'
  minTlsVersion: '1.2'
  healthCheckPath: '/healthz'
  http20Enabled: true
}

@description('Optional. Kind of web app.')
@allowed([
  'api'
  'app'
  'app,container,windows'
  'app,linux'
  'app,linux,container'
  'functionapp'
  'functionapp,linux'
  'functionapp,linux,container'
  'functionapp,linux,container,azurecontainerapps'
  'functionapp,workflowapp'
  'functionapp,workflowapp,linux'
  'linux,api'
])
param kind string = 'app'

// ======================== //
// Container Support        //
// ======================== //

@description('Optional. The container image name and optional tag for container-based deployments (e.g. "mcr.microsoft.com/appsvc/staticsite:latest"). Only used when kind contains "container".')
param containerImageName string = ''

@description('Optional. The container registry URL for private registries (e.g. "https://myregistry.azurecr.io"). Only used when kind contains "container" and a private registry is used.')
param containerRegistryUrl string = ''

@description('Optional. The container registry username for private registries.')
param containerRegistryUsername string = ''

@description('Optional. The container registry password for private registries.')
@secure()
param containerRegistryPassword string = ''

// ======================== //
// Diagnostics              //
// ======================== //

@description('Optional. Diagnostic Settings for the App Service.')
param appserviceDiagnosticSettings diagnosticSettingFullType[]?

@description('Optional. Diagnostic Settings for the App Service Plan.')
param servicePlanDiagnosticSettings diagnosticSettingMetricsOnlyType[]?

@description('Optional. Diagnostic Settings for the ASE.')
param aseDiagnosticSettings diagnosticSettingLogsOnlyType[]?

// ======================== //
// Variables                //
// ======================== //

var webAppDnsZoneName = 'privatelink.azurewebsites.net'
var slotName = 'staging'

var deployPlan = empty(existingAppServicePlanId)
var resolvedServerFarmResourceId = plan.?outputs.?resourceId ?? existingAppServicePlanId

var isLinux = webAppBaseOs =~ 'linux'
var isContainer = contains(kind, 'container')
var isWindowsContainer = contains(kind, 'container') && contains(kind, 'windows')

// Merge container-specific site config properties
var containerSiteConfig = isContainer && !empty(containerImageName)
  ? union(siteConfig, isLinux
      ? { linuxFxVersion: 'DOCKER|${containerImageName}' }
      : { windowsFxVersion: 'DOCKER|${containerImageName}' })
  : siteConfig

// Container registry app settings for private registries
var containerRegistryAppSettings = isContainer && !empty(containerRegistryUrl)
  ? {
      DOCKER_REGISTRY_SERVER_URL: containerRegistryUrl
      ...(!empty(containerRegistryUsername)
        ? {
            DOCKER_REGISTRY_SERVER_USERNAME: containerRegistryUsername
            DOCKER_REGISTRY_SERVER_PASSWORD: containerRegistryPassword
          }
        : {})
    }
  : {}

// ============ //
// Dependencies //
// ============ //

module ase './ase.module.bicep' = if (deployAseV3) {
  name: '${uniqueString(deployment().name, location)}-ase'
  params: {
    name: aseName
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    subnetResourceId: subnetIdForVnetInjection
    zoneRedundant: zoneRedundant
    allowNewPrivateEndpointConnections: true
    virtualNetworkLinks: virtualNetworkLinks
    diagnosticSettings: aseDiagnosticSettings
  }
}

module appInsights 'br/public:avm/res/insights/component:0.7.1' = {
  name: '${uniqueString(deployment().name, location)}-appInsights'
  params: {
    name: 'appi-${webAppName}'
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    workspaceResourceId: logAnalyticsWorkspaceResourceId
    applicationType: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    retentionInDays: 90
    samplingPercentage: 100
  }
}

module plan 'br/public:avm/res/web/serverfarm:0.7.0' = if (deployPlan) {
  name: '${uniqueString(deployment().name, location, 'webapp')}-plan'
  params: {
    name: appServicePlanName
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    skuName: sku
    zoneRedundant: zoneRedundant
    kind: isLinux ? 'Linux' : 'Windows'
    perSiteScaling: perSiteScaling
    maximumElasticWorkerCount: (maximumElasticWorkerCount < 3 && zoneRedundant) ? 3 : maximumElasticWorkerCount
    reserved: isLinux
    targetWorkerCount: (targetWorkerCount < 3 && zoneRedundant) ? 3 : targetWorkerCount
    targetWorkerSize: targetWorkerSize
    hyperV: isWindowsContainer
    appServiceEnvironmentResourceId: ase.?outputs.?resourceId ?? ''
    diagnosticSettings: servicePlanDiagnosticSettings
  }
}

module webApp 'br/public:avm/res/web/site:0.22.0' = {
  name: '${uniqueString(deployment().name, location)}-webapp'
  params: {
    kind: kind
    name: webAppName
    location: location
    enableTelemetry: enableTelemetry
    serverFarmResourceId: resolvedServerFarmResourceId
    siteConfig: containerSiteConfig
    clientAffinityEnabled: false
    diagnosticSettings: appserviceDiagnosticSettings
    virtualNetworkSubnetResourceId: !(deployAseV3) ? subnetIdForVnetInjection : ''
    managedIdentities: {
      userAssignedResourceIds: [webAppUserAssignedManagedIdentity.outputs.resourceId]
    }
    configs: [
      {
        name: 'appsettings'
        applicationInsightResourceId: appInsights.outputs.resourceId
        properties: !empty(containerRegistryAppSettings) ? containerRegistryAppSettings : {}
      }
    ]
    slots: [
      {
        name: slotName
      }
    ]
    privateEndpoints: (!empty(subnetPrivateEndpointResourceId) && !deployAseV3)
      ? [
          {
            name: 'webApp'
            subnetResourceId: subnetPrivateEndpointResourceId
            privateDnsZoneGroup: {
              name: 'webApp'
              privateDnsZoneGroupConfigs: [
                {
                  name: webAppDnsZoneName
                  privateDnsZoneResourceId: webAppPrivateDnsZone.?outputs.?resourceId ?? ''
                }
              ]
            }
          }
        ]
      : []
    tags: tags
  }
}

module webAppPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = if (!empty(subnetPrivateEndpointResourceId) && !deployAseV3) {
  name: '${uniqueString(deployment().name, location, 'webapp')}-dnszone'
  params: {
    name: webAppDnsZoneName
    location: 'global'
    enableTelemetry: enableTelemetry
    virtualNetworkLinks: virtualNetworkLinks
    tags: tags
  }
}

module webAppUserAssignedManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.0' = {
  name: '${uniqueString(deployment().name, location, 'webapp')}-uami'
  params: {
    name: managedIdentityName
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
  }
}

module peWebAppSlot 'br/public:avm/res/network/private-endpoint:0.11.1' = if (!empty(subnetPrivateEndpointResourceId) && !deployAseV3) {
  name: '${uniqueString(deployment().name, location, 'webapp')}-slot-${slotName}'
  params: {
    name: take('pe-${webAppName}-slot-${slotName}', 64)
    location: location
    enableTelemetry: enableTelemetry
    tags: tags
    privateDnsZoneGroup: (!empty(subnetPrivateEndpointResourceId) && !deployAseV3)
      ? {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: webAppPrivateDnsZone.?outputs.?resourceId ?? ''
            }
          ]
        }
      : null
    subnetResourceId: subnetPrivateEndpointResourceId
    privateLinkServiceConnections: [
      {
        name: 'webApp'
        properties: {
          privateLinkServiceId: webApp.outputs.resourceId
          groupIds: ['sites-${slotName}']
        }
      }
    ]
  }
}

// ======================== //
// Outputs                  //
// ======================== //

@description('The name of the web app.')
output webAppName string = webApp.outputs.name

@description('The default hostname of the web app.')
output webAppHostName string = webApp.outputs.defaultHostname

@description('The resource ID of the web app.')
output webAppResourceId string = webApp.outputs.resourceId

@description('The location of the web app.')
output webAppLocation string = webApp.outputs.location

@description('The principal ID of the user-assigned managed identity for the web app.')
output webAppSystemAssignedPrincipalId string = webAppUserAssignedManagedIdentity.outputs.principalId

@description('The resource ID of the App Service Plan used (either created or pre-existing).')
output appServicePlanResourceId string = resolvedServerFarmResourceId

@description('The Internal ingress IP of the ASE.')
output internalInboundIpAddress string = ase.?outputs.?internalInboundIpAddress ?? ''

@description('The name of the ASE.')
output aseName string = ase.?outputs.?name ?? ''
