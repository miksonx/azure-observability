variable "resource_group_name" {
  type        = string
  description = "Name of the resource group for the platform observability infrastructure"
}

variable "location" {
  type        = string
  description = "Azure region for all platform resources"
}

variable "cluster_name" {
  type        = string
  description = "Log Analytics dedicated cluster name"
}

variable "cluster_capacity_reservation_gb" {
  type        = number
  description = "Commitment tier in GB/day"
  default     = 100
}

variable "platform_workspace_name" {
  type        = string
  description = "Name of the central platform Log Analytics workspace"
}

variable "retention_in_days" {
  type        = number
  description = "Default data retention in days (30–730)"
  default     = 90
}

variable "key_vault_name" {
  type        = string
  description = "Key Vault name for the Customer-Managed Key"
}

variable "key_vault_key_name" {
  type        = string
  description = "Name of the CMK key inside Key Vault"
  default     = "log-analytics-cmk"
}

variable "key_expiry_days" {
  type        = number
  description = "CMK key expiry in days; automatic rotation fires 90 days before expiry"
  default     = 365
}

variable "key_vault_public_network_access_enabled" {
  type        = bool
  description = "Allow public internet access to Key Vault (false = private endpoint only)"
  default     = false
}

variable "key_vault_allowed_ips" {
  type        = list(string)
  description = "Public IP CIDR ranges allowed when public access is enabled"
  default     = []
}

variable "key_vault_private_endpoint_subnet_id" {
  type        = string
  description = "Subnet ID for the Key Vault private endpoint (null = no private endpoint)"
  default     = null
}

variable "private_dns_zone_resource_group_name" {
  type        = string
  description = "Resource group of the privatelink.vaultcore.azure.net DNS zone"
  default     = null
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all platform resources"
  default     = {}
}
