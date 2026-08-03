output "resource_group_name" {
  value       = azurerm_resource_group.consumer.name
  description = "Consumer resource group name (separate RG enables billing isolation per consumer)"
}

output "resource_group_id" {
  value       = azurerm_resource_group.consumer.id
  description = "Consumer resource group resource ID"
}

output "workspace_id" {
  value       = azurerm_log_analytics_workspace.consumer.id
  description = "Consumer workspace resource ID"
}

output "workspace_name" {
  value       = azurerm_log_analytics_workspace.consumer.name
  description = "Consumer workspace name"
}

output "workspace_customer_id" {
  value       = azurerm_log_analytics_workspace.consumer.workspace_id
  description = "Consumer workspace customer ID (used in agent / DCR configuration)"
}
