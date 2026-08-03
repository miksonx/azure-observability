variable "resource_group_name" {
  type        = string
  description = "Resource group where the Azure Monitor Workspace (Prometheus) is created"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "monitor_workspace_name" {
  type        = string
  description = "Name of the Azure Monitor Workspace (managed Prometheus endpoint)"
  default     = "amw-observability-prod"
}

variable "public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Allow public access to the Prometheus query endpoint.
    Set to false for enterprise deployments — requires AMPLS-linked private endpoint for query access.
    Ingestion always requires the Data Collection Endpoint (DCE) which has its own private endpoint.
  EOT
  default     = false
}

variable "platform_workspace_id" {
  type        = string
  description = "Resource ID of the central platform Log Analytics workspace"
}

variable "consumer_workspace_ids" {
  type        = map(string)
  description = "Map of consumer name → Log Analytics workspace resource ID"
  default     = {}
}

variable "grafana_managed_identity_principal_id" {
  type        = string
  description = "Principal ID of the external Grafana instance's managed identity — granted Monitoring Reader on the AMW and Log Analytics Reader on all workspaces"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all Prometheus resources"
  default     = {}
}
