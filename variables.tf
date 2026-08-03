# ─────────────────────────────────────────
# Subscription / tenant
# ─────────────────────────────────────────
variable "subscription_id" {
  type        = string
  description = "Azure subscription ID for all platform resources"
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID (required for Key Vault configuration)"
}

# ─────────────────────────────────────────
# Location / environment
# ─────────────────────────────────────────
variable "location" {
  type        = string
  description = "Primary Azure region for all resources"
  default     = "westeurope"
}

variable "environment" {
  type        = string
  description = "Environment label applied to resource names and tags"
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags merged into every resource"
  default     = {}
}

# ─────────────────────────────────────────
# Platform — dedicated cluster
# ─────────────────────────────────────────
variable "platform_resource_group_name" {
  type        = string
  description = "Resource group that holds the shared observability platform"
  default     = "rg-observability-platform-prod"
}

variable "cluster_name" {
  type        = string
  description = "Log Analytics dedicated cluster name (must be unique within the subscription)"
  default     = "lac-observability-prod"
}

variable "cluster_capacity_reservation_gb" {
  type        = number
  description = "Committed data ingestion tier in GB/day (min 100, increments: 100, 200, 300, 400, 500, 1000, 2000, 5000)"
  default     = 100

  validation {
    condition     = contains([100, 200, 300, 400, 500, 1000, 2000, 5000], var.cluster_capacity_reservation_gb)
    error_message = "Valid commitment tiers are 100, 200, 300, 400, 500, 1000, 2000, 5000 GB/day."
  }
}

variable "platform_workspace_name" {
  type        = string
  description = "Name of the central platform workspace (infrastructure / platform telemetry)"
  default     = "law-platform-prod"
}

variable "default_retention_in_days" {
  type        = number
  description = "Default data retention period in days applied to all workspaces (30–730)"
  default     = 90

  validation {
    condition     = var.default_retention_in_days >= 30 && var.default_retention_in_days <= 730
    error_message = "Retention must be between 30 and 730 days."
  }
}

# ─────────────────────────────────────────
# Platform — Key Vault / CMK
# ─────────────────────────────────────────
variable "key_vault_name" {
  type        = string
  description = "Globally unique Key Vault name (3–24 alphanumeric chars and hyphens)"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must be 3–24 characters, start with a letter, and contain only alphanumerics and hyphens."
  }
}

variable "key_vault_key_name" {
  type        = string
  description = "Name of the RSA key used as the Customer-Managed Key for the dedicated cluster"
  default     = "log-analytics-cmk"
}

variable "key_expiry_days" {
  type        = number
  description = "Number of days before the CMK key expires; rotation is triggered 90 days before expiry"
  default     = 365
}

# ─────────────────────────────────────────
# Platform — network access (Key Vault)
# ─────────────────────────────────────────
variable "key_vault_public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Set to false (recommended for production) to restrict Key Vault to private endpoints only.
    Requires a private endpoint + DNS zone to be configured, and the Terraform runner must
    have private-network access (e.g., self-hosted agent in the same VNet).
    Set to true only for initial bootstrap or pipelines without private connectivity.
  EOT
  default     = false
}

variable "key_vault_allowed_ips" {
  type        = list(string)
  description = "List of public IP CIDR ranges allowed to reach Key Vault when public access is enabled (e.g., CI runner egress IPs)"
  default     = []
}

variable "key_vault_private_endpoint_subnet_id" {
  type        = string
  description = "Subnet resource ID for the Key Vault private endpoint. Required when key_vault_public_network_access_enabled = false"
  default     = null
}

variable "private_dns_zone_resource_group_name" {
  type        = string
  description = "Resource group containing the privatelink.vaultcore.azure.net private DNS zone (required when private endpoint is enabled)"
  default     = null
}

# ─────────────────────────────────────────
# Networking — spoke VNet
# ─────────────────────────────────────────
variable "network_resource_group_name" {
  type        = string
  description = "Resource group for the observability spoke networking resources"
  default     = "rg-observability-network-prod"
}

variable "vnet_name" {
  type        = string
  description = "Name of the observability spoke VNet"
  default     = "vnet-observability-prod"
}

variable "vnet_address_space" {
  type        = string
  description = "CIDR block for the spoke VNet (e.g. '10.100.0.0/23')"
  default     = "10.100.0.0/23"
}

variable "private_endpoints_subnet_cidr" {
  type        = string
  description = "CIDR for the private-endpoints subnet within the spoke VNet (min /28)"
  default     = "10.100.0.0/26"
}

variable "hub_vnet_id" {
  type        = string
  description = "Resource ID of the central hub VNet to peer with"
}

variable "hub_vnet_name" {
  type        = string
  description = "Name of the hub VNet — required only when manage_hub_peering = true"
  default     = null
}

variable "hub_vnet_resource_group_name" {
  type        = string
  description = "Resource group of the hub VNet — required only when manage_hub_peering = true"
  default     = null
}

variable "manage_hub_peering" {
  type        = bool
  description = "When true, Terraform also creates the hub→spoke peering (requires Contributor on hub VNet RG)"
  default     = false
}

variable "use_hub_gateway" {
  type        = bool
  description = "Set to true when the hub hosts a VPN/ExpressRoute gateway and spoke should transit it"
  default     = false
}

variable "hub_firewall_private_ip" {
  type        = string
  description = "Private IP of the hub NVA/Azure Firewall — when set, a UDR for 0.0.0.0/0 is created"
  default     = null
}

# ─────────────────────────────────────────
# AMPLS (Azure Monitor Private Link Scope)
# Provided centrally — we register workspaces as scoped services
# ─────────────────────────────────────────
variable "ampls_name" {
  type        = string
  description = "Name of the centrally-managed Azure Monitor Private Link Scope"
}

variable "ampls_resource_group_name" {
  type        = string
  description = "Resource group of the centrally-managed AMPLS (deploying SP needs Contributor here)"
}

# ─────────────────────────────────────────
# Prometheus / Azure Monitor Workspace
# ─────────────────────────────────────────
variable "monitor_workspace_name" {
  type        = string
  description = "Name of the Azure Monitor Workspace (managed Prometheus endpoint)"
  default     = "amw-observability-prod"
}

variable "grafana_managed_identity_principal_id" {
  type        = string
  description = "Object ID of the external Grafana instance's managed identity — granted Monitoring Reader on AMW and Log Analytics Reader on all workspaces"
}

# ─────────────────────────────────────────
# Grafana data source registration (optional)
# Requires grafana/grafana provider ~> 3.0
# ─────────────────────────────────────────
variable "grafana_endpoint" {
  type        = string
  description = "URL of the external Grafana instance (e.g. 'https://grafana.contoso.com'). When null, no Grafana data sources are provisioned"
  default     = null
}

variable "grafana_service_account_token" {
  type        = string
  description = "Grafana service account token with Editor or Admin permissions. Sensitive — pass via environment variable TF_VAR_grafana_service_account_token"
  default     = null
  sensitive   = true
}

# ─────────────────────────────────────────
# Consumers
# ─────────────────────────────────────────
variable "consumers" {
  description = <<-EOT
    Map of consumer teams to provision. Each key is the consumer identifier (used in resource names).
    Each value configures the workspace and access control for that consumer.
  EOT
  type = map(object({
    retention_in_days      = optional(number)
    workspace_contributors = optional(list(string), [])  # AAD object IDs — Log Analytics Contributor
    workspace_readers      = optional(list(string), [])  # AAD object IDs — Log Analytics Reader
    extra_tags             = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.consumers) : can(regex("^[a-z0-9-]{2,20}$", k))])
    error_message = "Consumer keys must be 2–20 lowercase alphanumeric characters or hyphens."
  }
}
