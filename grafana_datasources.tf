# ─────────────────────────────────────────────────────────────────────────────
# Grafana data source registration (optional)
#
# When grafana_endpoint and grafana_service_account_token are both set,
# Terraform configures data sources directly in the external Grafana instance.
# When either is null (default), no Grafana resources are created.
#
# The Grafana instance is provided by another team — this module only adds
# data sources; it does not create or manage the Grafana instance itself.
#
# Provider: grafana/grafana ~> 3.0 (declared in providers.tf)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  grafana_enabled = var.grafana_endpoint != null && var.grafana_service_account_token != null
}

# ─────────────────────────────────────────────────────────────────────────────
# Prometheus data source
#
# Targets the Azure Monitor Workspace PromQL query endpoint.
# Authentication: Azure managed identity of the Grafana instance.
# The Grafana MI must have Monitoring Reader on the AMW (granted by the
# prometheus module's azurerm_role_assignment.grafana_amw_reader).
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_data_source" "prometheus" {
  count = local.grafana_enabled ? 1 : 0

  name = "Azure Managed Prometheus — ${var.environment}"
  type = "prometheus"
  url  = module.prometheus.query_endpoint

  json_data_encoded = jsonencode({
    httpMethod = "POST"
    # Authenticate using the Grafana instance's managed identity (no stored credentials)
    azureCredentials = {
      authType = "msi"
    }
    timeInterval = "60s"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor data source (covers Log Analytics + Azure metrics)
#
# A single Azure Monitor data source in Grafana can target multiple
# Log Analytics workspaces via cross-workspace queries. The workspace IDs
# are exposed as Grafana variables so dashboard authors can switch context.
#
# Authentication: Azure managed identity of the Grafana instance.
# The Grafana MI must have Log Analytics Reader on each workspace (granted by
# the prometheus module's azurerm_role_assignment.grafana_*_workspace_reader).
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_data_source" "azure_monitor" {
  count = local.grafana_enabled ? 1 : 0

  name = "Azure Monitor — ${var.environment}"
  type = "grafana-azure-monitor-datasource"

  json_data_encoded = jsonencode({
    subscriptionId = var.subscription_id
    tenantId       = var.tenant_id
    # MSI auth — Grafana uses its own managed identity; no client secret needed
    azureAuthType  = "msi"
    # Default Log Analytics workspace for new panels (platform workspace)
    logAnalyticsDefaultWorkspace = module.platform.platform_workspace_customer_id
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Grafana folder — organises observability dashboards
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_folder" "observability" {
  count = local.grafana_enabled ? 1 : 0

  title = "Centralized Observability — ${var.environment}"
  uid   = "centralized-obs-${var.environment}"
}
