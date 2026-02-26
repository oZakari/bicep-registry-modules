// ======================== //
// Shared User-Defined Types //
// ======================== //

@export()
@description('Describes a virtual network link for a private DNS zone.')
type virtualNetworkLinkType = {
  @description('Required. The name of the virtual network link.')
  name: string

  @description('Required. The resource ID of the virtual network.')
  virtualNetworkResourceId: string

  @description('Optional. Is auto-registration of virtual machine records in the virtual network in the Private DNS zone enabled.')
  registrationEnabled: bool?
}

@export()
@description('Describes a cluster setting for the App Service Environment.')
type clusterSettingType = {
  @description('Required. The name of the cluster setting.')
  name: string

  @description('Required. The value of the cluster setting.')
  value: string
}

@export()
@description('User-defined type for site configuration properties.')
type siteConfigType = {
  @description('Optional. Whether the web app should always be loaded.')
  alwaysOn: bool?

  @description('Optional. State of FTP / FTPS service.')
  ftpsState: ('AllAllowed' | 'Disabled' | 'FtpsOnly')?

  @description('Optional. Configures the minimum version of TLS required for SSL requests.')
  minTlsVersion: ('1.0' | '1.1' | '1.2' | '1.3')?

  @description('Optional. Health check path. Used by App Service load balancers to determine instance health.')
  healthCheckPath: string?

  @description('Optional. Whether HTTP 2.0 is enabled.')
  http20Enabled: bool?

  @description('Optional. Linux app framework and version string for container deployments (e.g. "DOCKER|image:tag").')
  linuxFxVersion: string?

  @description('Optional. Windows app framework and version string for container deployments (e.g. "DOCKER|image:tag").')
  windowsFxVersion: string?
}
