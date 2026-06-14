output "monitor_workspace_id" {
  value       = azurerm_monitor_workspace.main.id
  description = "Resource ID of the Azure Monitor Workspace"
}

output "monitor_workspace_name" {
  value       = azurerm_monitor_workspace.main.name
  description = "Name of the Azure Monitor Workspace"
}

output "query_endpoint" {
  value       = azurerm_monitor_workspace.main.query_endpoint
  description = "Prometheus-compatible query endpoint URL — configure as the Grafana Prometheus data source URL"
}

output "default_data_collection_endpoint_id" {
  value       = azurerm_monitor_workspace.main.default_data_collection_endpoint_id
  description = "Default DCE resource ID — used when creating Data Collection Rule associations on AKS clusters"
}

output "default_data_collection_rule_id" {
  value       = azurerm_monitor_workspace.main.default_data_collection_rule_id
  description = "Default DCR resource ID created by the managed Prometheus workspace"
}

output "prometheus_dcr_id" {
  value       = azurerm_monitor_data_collection_rule.prometheus.id
  description = "Resource ID of the Prometheus scraping DCR — consumer teams associate this with their AKS clusters"
}

output "prometheus_dcr_name" {
  value       = azurerm_monitor_data_collection_rule.prometheus.name
  description = "Name of the Prometheus scraping DCR"
}
