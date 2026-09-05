// ALDC quality metrics — Application Insights for the DSC estate.
//
// One workspace-based Application Insights resource, plus the Log Analytics workspace it
// requires (classic, non-workspace resources are retired; workspace-based is the only mode
// to deploy into now). Everything the plugin sends lands in `customEvents` as `AldcPhase`,
// with the numbers in `customMeasurements` and the dimensions in `customDimensions`.
//
// Deploy:
//   az group create -n rg-aldc-metrics -l westeurope
//   az deployment group create -g rg-aldc-metrics -f main.bicep -p environment=prod
//
// Then read the connection string and distribute it as APPLICATIONINSIGHTS_CONNECTION_STRING
// (see README.md — it is not a secret in the credential sense, but it is a write key: treat
// it as configuration, not as something to commit).

@description('Azure region. Keep it close to the developers so ingestion latency stays low.')
param location string = resourceGroup().location

@description('Short environment tag, used in resource names.')
@allowed(['dev', 'test', 'prod'])
param environment string = 'prod'

@description('Base name for the resources.')
param baseName string = 'aldc-metrics'

@description('How long to keep the data. 30 days is free on Log Analytics; beyond that is billed.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Daily ingestion cap in GB. A hard stop so a runaway loop cannot produce a bill. -1 disables the cap.')
param dailyQuotaGb int = 1

var workspaceName = 'log-${baseName}-${environment}'
var appInsightsName = 'appi-${baseName}-${environment}'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      // Pay-as-you-go. These records are tiny — a phase is well under 1 KB — so the
      // realistic monthly volume for a consultancy is a few MB.
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: {
    purpose: 'aldc-quality-metrics'
    environment: environment
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'other'
  properties: {
    Application_Type: 'other'
    WorkspaceResourceId: workspace.id
    // Ingestion uses the instrumentation key in the connection string. Leave local auth on:
    // the plugin posts from developer machines with no managed identity to borrow.
    DisableLocalAuth: false
    // Never sample: the whole point is counting every phase, and the volume is trivial.
    SamplingPercentage: 100
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: {
    purpose: 'aldc-quality-metrics'
    environment: environment
  }
}

@description('Set this as APPLICATIONINSIGHTS_CONNECTION_STRING on developer machines and CI.')
output connectionString string = appInsights.properties.ConnectionString

@description('Resource id, for wiring a workbook or an alert rule.')
output appInsightsId string = appInsights.id

output workspaceId string = workspace.id
