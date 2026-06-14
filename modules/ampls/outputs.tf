output "ampls_id" {
  value       = data.azurerm_monitor_private_link_scope.central.id
  description = "Resource ID of the central AMPLS (read from data source)"
}

output "scoped_service_ids" {
  value = merge(
    { platform = azurerm_monitor_private_link_scoped_service.platform_workspace.id },
    { for k, v in azurerm_monitor_private_link_scoped_service.consumer_workspaces : k => v.id },
    var.prometheus_workspace_id != null ? { prometheus = azurerm_monitor_private_link_scoped_service.prometheus_workspace[0].id } : {}
  )
  description = "Map of all AMPLS scoped-service resource IDs registered by this module"
}
