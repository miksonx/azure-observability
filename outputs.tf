# ─────────────────────────────────────────
# Platform cluster
# ─────────────────────────────────────────

output "platform_cluster_id" {
  value       = module.platform.cluster_id
  description = "Resource ID of the Log Analytics dedicated cluster"
}

output "platform_cluster_name" {
  value       = module.platform.cluster_name
  description = "Name of the Log Analytics dedicated cluster"
}

output "platform_workspace_id" {
  value       = module.platform.platform_workspace_id
  description = "Resource ID of the central platform workspace"
}

output "platform_workspace_customer_id" {
  value       = module.platform.platform_workspace_customer_id
  description = "Platform workspace customer ID (used in agent and DCR configuration)"
}

output "key_vault_id" {
  value       = module.platform.key_vault_id
  description = "Resource ID of the Key Vault holding the CMK"
}

# ─────────────────────────────────────────
# Consumer workspaces
# ─────────────────────────────────────────

output "consumer_workspaces" {
  value = {
    for k, v in module.consumers : k => {
      resource_group_name   = v.resource_group_name
      workspace_id          = v.workspace_id
      workspace_name        = v.workspace_name
      workspace_customer_id = v.workspace_customer_id
    }
  }
  description = "Per-consumer workspace details — resource group, workspace ID, customer ID"
}

# ─────────────────────────────────────────
# Networking
# ─────────────────────────────────────────

output "spoke_vnet_id" {
  value       = module.networking.vnet_id
  description = "Resource ID of the observability spoke VNet — provide to the hub team for the hub→spoke peering if manage_hub_peering = false"
}

output "private_endpoints_subnet_id" {
  value       = module.networking.private_endpoints_subnet_id
  description = "Subnet ID hosting private endpoints (Key Vault PE etc.)"
}

# ─────────────────────────────────────────
# AMPLS
# ─────────────────────────────────────────

output "ampls_scoped_service_ids" {
  value       = module.ampls.scoped_service_ids
  description = "Map of all AMPLS scoped-service resource IDs registered by this deployment"
}

# ─────────────────────────────────────────
# Prometheus / Grafana
# ─────────────────────────────────────────

output "prometheus_query_endpoint" {
  value       = module.prometheus.query_endpoint
  description = "Prometheus-compatible PromQL query endpoint — configure as the Grafana Prometheus data source URL"
}

output "prometheus_dcr_id" {
  value       = module.prometheus.prometheus_dcr_id
  description = "Prometheus scraping DCR resource ID — consumer teams associate this with their AKS clusters to enable managed Prometheus"
}

output "prometheus_default_dce_id" {
  value       = module.prometheus.default_data_collection_endpoint_id
  description = "Default Data Collection Endpoint resource ID for the Azure Monitor Workspace"
}

output "grafana_datasource_summary" {
  value = {
    prometheus_url              = module.prometheus.query_endpoint
    azure_monitor_workspace_id  = module.prometheus.monitor_workspace_id
    platform_workspace_customer_id = module.platform.platform_workspace_customer_id
    subscription_id             = var.subscription_id
    tenant_id                   = var.tenant_id
  }
  description = "Values the Grafana team needs to configure data sources manually (when grafana_endpoint is not set)"
}
