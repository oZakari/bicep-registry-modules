metadata name = 'Log Analytics Workspaces'
metadata description = 'This module deploys a Log Analytics Workspace.'
metadata owner = 'Azure/module-maintainers'

@description('Required. Name of the Log Analytics workspace.')
param name string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. The name of the SKU.')
@allowed([
  'CapacityReservation'
  'Free'
  'LACluster'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param skuName string = 'PerGB2018'

@minValue(100)
@maxValue(5000)
@description('Optional. The capacity reservation level in GB for this workspace, when CapacityReservation sku is selected. Must be in increments of 100 between 100 and 5000.')
param skuCapacityReservationLevel int = 100

@description('Optional. List of storage accounts to be read by the workspace.')
param storageInsightsConfigs array = []

@description('Optional. List of services to be linked.')
param linkedServices array = []

@description('Conditional. List of Storage Accounts to be linked. Required if \'forceCmkForQuery\' is set to \'true\' and \'savedSearches\' is not empty.')
param linkedStorageAccounts array = []

@description('Optional. Kusto Query Language searches to save.')
param savedSearches array = []

@description('Optional. LAW data export instances to be deployed.')
param dataExports array = []

@description('Optional. LAW data sources to configure.')
param dataSources array = []

@description('Optional. LAW custom tables to be deployed.')
param tables array = []

@description('Optional. List of gallerySolutions to be created in the log analytics workspace.')
param gallerySolutions gallerySolutionType[]?

@description('Optional. Onboard the Log Analytics Workspace to Sentinel. Requires \'SecurityInsights\' solution to be in gallerySolutions.')
param onboardWorkspaceToSentinel bool = false

@description('Optional. Number of days data will be retained for.')
@minValue(0)
@maxValue(730)
param dataRetention int = 365

@description('Optional. The workspace daily quota for ingestion.')
@minValue(-1)
param dailyQuotaGb int = -1

@description('Optional. The network access type for accessing Log Analytics ingestion.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForIngestion string = 'Enabled'

@description('Optional. The network access type for accessing Log Analytics query.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForQuery string = 'Enabled'

import { managedIdentityAllType } from 'br/public:avm/utl/types/avm-common-types:0.2.1'
@description('Optional. The managed identity definition for this resource. Only one type of identity is supported: system-assigned or user-assigned, but not both.')
param managedIdentities managedIdentityAllType?

@description('Optional. Set to \'true\' to use resource or workspace permissions and \'false\' (or leave empty) to require workspace permissions.')
param useResourcePermissions bool = false

@description('Optional. The diagnostic settings of the service.')
param diagnosticSettings diagnosticSettingType[]?

@description('Optional. Indicates whether customer managed storage is mandatory for query management.')
param forceCmkForQuery bool = true

import { lockType } from 'br/public:avm/utl/types/avm-common-types:0.2.1'
@description('Optional. The lock settings of the service.')
param lock lockType?

import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.2.1'
@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('Optional. Tags of the resource.')
param tags object?

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

var formattedUserAssignedIdentities = reduce(
  map((managedIdentities.?userAssignedResourceIds ?? []), (id) => { '${id}': {} }),
  {},
  (cur, next) => union(cur, next)
) // Converts the flat array to an object like { '${id1}': {}, '${id2}': {} }

var identity = !empty(managedIdentities)
  ? {
      type: (managedIdentities.?systemAssigned ?? false)
        ? 'SystemAssigned'
        : (!empty(managedIdentities.?userAssignedResourceIds ?? {}) ? 'UserAssigned' : 'None')
      userAssignedIdentities: !empty(formattedUserAssignedIdentities) ? formattedUserAssignedIdentities : null
    }
  : null

var builtInRoleNames = {
  Contributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  'Log Analytics Contributor': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293'
  )
  'Log Analytics Reader': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '73c42c96-874c-492b-b04d-ab87d138a893'
  )
  'Monitoring Contributor': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
  )
  'Monitoring Reader': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  )
  Owner: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
  Reader: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  'Role Based Access Control Administrator': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
  )
  'Security Admin': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'fb1c8493-542b-48eb-b624-b4c8fea62acd'
  )
  'Security Reader': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '39bc4728-0917-49c7-9d2c-d95423bc2eb4'
  )
  'User Access Administrator': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
  )
}

var formattedRoleAssignments = [
  for (roleAssignment, index) in (roleAssignments ?? []): union(roleAssignment, {
    roleDefinitionId: builtInRoleNames[?roleAssignment.roleDefinitionIdOrName] ?? (contains(
        roleAssignment.roleDefinitionIdOrName,
        '/providers/Microsoft.Authorization/roleDefinitions/'
      )
      ? roleAssignment.roleDefinitionIdOrName
      : subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAssignment.roleDefinitionIdOrName))
  })
]

#disable-next-line no-deployments-resources
resource avmTelemetry 'Microsoft.Resources/deployments@2024-03-01' = if (enableTelemetry) {
  name: '46d3xbcp.res.operationalinsights-workspace.${replace('-..--..-', '.', '-')}.${substring(uniqueString(deployment().name, location), 0, 4)}'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
      outputs: {
        telemetry: {
          type: 'String'
          value: 'For more information, see https://aka.ms/avm/TelemetryInfo'
        }
      }
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  location: location
  name: name
  tags: tags
  properties: {
    features: {
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: useResourcePermissions
    }
    sku: {
      name: skuName
      capacityReservationLevel: skuName == 'CapacityReservation' ? skuCapacityReservationLevel : null
    }
    retentionInDays: dataRetention
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
    forceCmkForQuery: forceCmkForQuery
  }
  identity: identity
}

resource logAnalyticsWorkspace_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [
  for (diagnosticSetting, index) in (diagnosticSettings ?? []): {
    name: diagnosticSetting.?name ?? '${name}-diagnosticSettings'
    properties: {
      storageAccountId: diagnosticSetting.?storageAccountResourceId
      workspaceId: (diagnosticSetting.?useThisWorkspace ?? false)
        ? logAnalyticsWorkspace.id
        : diagnosticSetting.?workspaceResourceId
      eventHubAuthorizationRuleId: diagnosticSetting.?eventHubAuthorizationRuleResourceId
      eventHubName: diagnosticSetting.?eventHubName
      metrics: [
        for group in (diagnosticSetting.?metricCategories ?? [{ category: 'AllMetrics' }]): {
          category: group.category
          enabled: group.?enabled ?? true
          timeGrain: null
        }
      ]
      logs: [
        for group in (diagnosticSetting.?logCategoriesAndGroups ?? [{ categoryGroup: 'allLogs' }]): {
          categoryGroup: group.?categoryGroup
          category: group.?category
          enabled: group.?enabled ?? true
        }
      ]
      marketplacePartnerId: diagnosticSetting.?marketplacePartnerResourceId
      logAnalyticsDestinationType: diagnosticSetting.?logAnalyticsDestinationType
    }
    scope: logAnalyticsWorkspace
  }
]

module logAnalyticsWorkspace_storageInsightConfigs 'storage-insight-config/main.bicep' = [
  for (storageInsightsConfig, index) in storageInsightsConfigs: {
    name: '${uniqueString(deployment().name, location)}-LAW-StorageInsightsConfig-${index}'
    params: {
      logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
      containers: storageInsightsConfig.?containers
      tables: storageInsightsConfig.?tables
      storageAccountResourceId: storageInsightsConfig.storageAccountResourceId
    }
  }
]

module logAnalyticsWorkspace_linkedServices 'linked-service/main.bicep' = [
  for (linkedService, index) in linkedServices: {
    name: '${uniqueString(deployment().name, location)}-LAW-LinkedService-${index}'
    params: {
      logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
      name: linkedService.name
      resourceId: linkedService.?resourceId
      writeAccessResourceId: linkedService.?writeAccessResourceId
    }
  }
]

module logAnalyticsWorkspace_linkedStorageAccounts 'linked-storage-account/main.bicep' = [
  for (linkedStorageAccount, index) in linkedStorageAccounts: {
    name: '${uniqueString(deployment().name, location)}-LAW-LinkedStorageAccount-${index}'
    params: {
      logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
      name: linkedStorageAccount.name
      resourceId: linkedStorageAccount.resourceId
    }
  }
]

module logAnalyticsWorkspace_savedSearches 'saved-search/main.bicep' = [
  for (savedSearch, index) in savedSearches: {
    name: '${uniqueString(deployment().name, location)}-LAW-SavedSearch-${index}'
    params: {
      logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
      name: '${savedSearch.name}${uniqueString(deployment().name)}'
      etag: savedSearch.?etag
      displayName: savedSearch.displayName
      category: savedSearch.category
      query: savedSearch.query
      functionAlias: savedSearch.?functionAlias
      functionParameters: savedSearch.?functionParameters
      version: savedSearch.?version
    }
    dependsOn: [
      logAnalyticsWorkspace_linkedStorageAccounts
    ]
  }
]

module logAnalyticsWorkspace_dataExports 'data-export/main.bicep' = [
  for (dataExport, index) in dataExports: {
    name: '${uniqueString(deployment().name, location)}-LAW-DataExport-${index}'
    params: {
      workspaceName: logAnalyticsWorkspace.name
      name: dataExport.name
      destination: dataExport.?destination
      enable: dataExport.?enable
      tableNames: dataExport.?tableNames
    }
  }
]

module logAnalyticsWorkspace_dataSources 'data-source/main.bicep' = [
  for (dataSource, index) in dataSources: {
    name: '${uniqueString(deployment().name, location)}-LAW-DataSource-${index}'
    params: {
      logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
      name: dataSource.name
      kind: dataSource.kind
      linkedResourceId: dataSource.?linkedResourceId
      eventLogName: dataSource.?eventLogName
      eventTypes: dataSource.?eventTypes
      objectName: dataSource.?objectName
      instanceName: dataSource.?instanceName
      intervalSeconds: dataSource.?intervalSeconds
      counterName: dataSource.?counterName
      state: dataSource.?state
      syslogName: dataSource.?syslogName
      syslogSeverities: dataSource.?syslogSeverities
      performanceCounters: dataSource.?performanceCounters
    }
  }
]

module logAnalyticsWorkspace_tables 'table/main.bicep' = [
  for (table, index) in tables: {
    name: '${uniqueString(deployment().name, location)}-LAW-Table-${index}'
    params: {
      workspaceName: logAnalyticsWorkspace.name
      name: table.name
      plan: table.?plan
      schema: table.?schema
      retentionInDays: table.?retentionInDays
      totalRetentionInDays: table.?totalRetentionInDays
      restoredLogs: table.?restoredLogs
      searchResults: table.?searchResults
      roleAssignments: table.?roleAssignments
    }
  }
]

module logAnalyticsWorkspace_solutions 'br/public:avm/res/operations-management/solution:0.3.0' = [
  for (gallerySolution, index) in gallerySolutions ?? []: if (!empty(gallerySolutions)) {
    name: '${uniqueString(deployment().name, location)}-LAW-Solution-${index}'
    params: {
      name: gallerySolution.name
      location: location
      logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
      plan: gallerySolution.plan
      enableTelemetry: gallerySolution.?enableTelemetry ?? enableTelemetry
    }
  }
]

// Onboard the Log Analytics Workspace to Sentinel if SecurityInsights is in gallerySolutions and onboardWorkspaceToSentinel is set to true
resource logAnalyticsWorkspace_sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = if (!empty(filter(
  gallerySolutions ?? [],
  item => startsWith(item.name, 'SecurityInsights')
)) && onboardWorkspaceToSentinel) {
  name: 'default'
  scope: logAnalyticsWorkspace
  properties: {}
}

resource logAnalyticsWorkspace_lock 'Microsoft.Authorization/locks@2020-05-01' = if (!empty(lock ?? {}) && lock.?kind != 'None') {
  name: lock.?name ?? 'lock-${name}'
  properties: {
    level: lock.?kind ?? ''
    notes: lock.?kind == 'CanNotDelete'
      ? 'Cannot delete resource or child resources.'
      : 'Cannot delete or modify the resource or child resources.'
  }
  scope: logAnalyticsWorkspace
}

resource logAnalyticsWorkspace_roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (roleAssignment, index) in (formattedRoleAssignments ?? []): {
    name: roleAssignment.?name ?? guid(
      logAnalyticsWorkspace.id,
      roleAssignment.principalId,
      roleAssignment.roleDefinitionId
    )
    properties: {
      roleDefinitionId: roleAssignment.roleDefinitionId
      principalId: roleAssignment.principalId
      description: roleAssignment.?description
      principalType: roleAssignment.?principalType
      condition: roleAssignment.?condition
      conditionVersion: !empty(roleAssignment.?condition) ? (roleAssignment.?conditionVersion ?? '2.0') : null // Must only be set if condtion is set
      delegatedManagedIdentityResourceId: roleAssignment.?delegatedManagedIdentityResourceId
    }
    scope: logAnalyticsWorkspace
  }
]

@description('The resource ID of the deployed log analytics workspace.')
output resourceId string = logAnalyticsWorkspace.id

@description('The resource group of the deployed log analytics workspace.')
output resourceGroupName string = resourceGroup().name

@description('The name of the deployed log analytics workspace.')
output name string = logAnalyticsWorkspace.name

@description('The ID associated with the workspace.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The location the resource was deployed into.')
output location string = logAnalyticsWorkspace.location

@description('The principal ID of the system assigned identity.')
output systemAssignedMIPrincipalId string = logAnalyticsWorkspace.?identity.?principalId ?? ''

// =============== //
//   Definitions   //
// =============== //

type diagnosticSettingType = {
  @description('Optional. The name of diagnostic setting.')
  name: string?

  @description('Optional. The name of logs that will be streamed. "allLogs" includes all possible logs for the resource. Set to `[]` to disable log collection.')
  logCategoriesAndGroups: {
    @description('Optional. Name of a Diagnostic Log category for a resource type this setting is applied to. Set the specific logs to collect here.')
    category: string?

    @description('Optional. Name of a Diagnostic Log category group for a resource type this setting is applied to. Set to `allLogs` to collect all logs.')
    categoryGroup: string?

    @description('Optional. Enable or disable the category explicitly. Default is `true`.')
    enabled: bool?
  }[]?

  @description('Optional. The name of metrics that will be streamed. "allMetrics" includes all possible metrics for the resource. Set to `[]` to disable metric collection.')
  metricCategories: {
    @description('Required. Name of a Diagnostic Metric category for a resource type this setting is applied to. Set to `AllMetrics` to collect all metrics.')
    category: string

    @description('Optional. Enable or disable the category explicitly. Default is `true`.')
    enabled: bool?
  }[]?

  @description('Optional. A string indicating whether the export to Log Analytics should use the default destination type, i.e. AzureDiagnostics, or use a destination type.')
  logAnalyticsDestinationType: ('Dedicated' | 'AzureDiagnostics' | null)?

  @description('Optional. Instead of using an external reference, use the deployed instance as the target for its diagnostic settings. If set to `true`, the `workspaceResourceId` property is ignored.')
  useThisWorkspace: bool?

  @description('Optional. Resource ID of the diagnostic log analytics workspace. For security reasons, it is recommended to set diagnostic settings to send data to either storage account, log analytics workspace or event hub.')
  workspaceResourceId: string?

  @description('Optional. Resource ID of the diagnostic storage account. For security reasons, it is recommended to set diagnostic settings to send data to either storage account, log analytics workspace or event hub.')
  storageAccountResourceId: string?

  @description('Optional. Resource ID of the diagnostic event hub authorization rule for the Event Hubs namespace in which the event hub should be created or streamed to.')
  eventHubAuthorizationRuleResourceId: string?

  @description('Optional. Name of the diagnostic event hub within the namespace to which logs are streamed. Without this, an event hub is created for each log category. For security reasons, it is recommended to set diagnostic settings to send data to either storage account, log analytics workspace or event hub.')
  eventHubName: string?

  @description('Optional. The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic Logs.')
  marketplacePartnerResourceId: string?
}

import { solutionPlanType } from 'br/public:avm/res/operations-management/solution:0.3.0'

@export()
type gallerySolutionType = {
  @description('''Required. Name of the solution.
  For solutions authored by Microsoft, the name must be in the pattern: `SolutionType(WorkspaceName)`, for example: `AntiMalware(contoso-Logs)`.
  For solutions authored by third parties, the name should be in the pattern: `SolutionType[WorkspaceName]`, for example `MySolution[contoso-Logs]`.
  The solution type is case-sensitive.''')
  name: string

  @description('Required. Plan for solution object supported by the OperationsManagement resource provider.')
  plan: solutionPlanType
}
