output "cluster_id" {
  value       = azurerm_log_analytics_cluster.main.id
  description = "Resource ID of the Log Analytics dedicated cluster"
}

output "cluster_name" {
  value       = azurerm_log_analytics_cluster.main.name
  description = "Name of the Log Analytics dedicated cluster"
}

output "platform_workspace_id" {
  value       = azurerm_log_analytics_workspace.platform.id
  description = "Resource ID of the central platform workspace"
}

output "platform_workspace_customer_id" {
  value       = azurerm_log_analytics_workspace.platform.workspace_id
  description = "Platform workspace customer/tenant ID (used in agent configuration)"
}

output "key_vault_id" {
  value       = azurerm_key_vault.main.id
  description = "Resource ID of the Key Vault holding the CMK"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.main.vault_uri
  description = "URI of the Key Vault"
}

output "cluster_identity_principal_id" {
  value       = azurerm_user_assigned_identity.cluster.principal_id
  description = "Principal ID of the cluster managed identity (for additional RBAC assignments)"
}

output "resource_group_name" {
  value       = azurerm_resource_group.platform.name
  description = "Platform resource group name"
}
