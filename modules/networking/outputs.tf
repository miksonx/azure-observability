output "vnet_id" {
  value       = azurerm_virtual_network.spoke.id
  description = "Resource ID of the spoke VNet"
}

output "vnet_name" {
  value       = azurerm_virtual_network.spoke.name
  description = "Name of the spoke VNet"
}

output "private_endpoints_subnet_id" {
  value       = azurerm_subnet.private_endpoints.id
  description = "Subnet ID for private endpoints — pass to the platform module for Key Vault PE"
}

output "resource_group_name" {
  value       = azurerm_resource_group.network.name
  description = "Networking resource group name"
}

output "resource_group_id" {
  value       = azurerm_resource_group.network.id
  description = "Networking resource group resource ID"
}
