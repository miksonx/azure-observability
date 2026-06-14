variable "ampls_name" {
  type        = string
  description = "Name of the centrally-managed Azure Monitor Private Link Scope"
}

variable "ampls_resource_group_name" {
  type        = string
  description = "Resource group of the centrally-managed AMPLS (scoped services are created here)"
}

variable "platform_workspace_name" {
  type        = string
  description = "Name of the platform workspace (used in the scoped-service resource name)"
}

variable "platform_workspace_id" {
  type        = string
  description = "Resource ID of the central platform Log Analytics workspace to link to AMPLS"
}

variable "consumer_workspaces" {
  type        = map(string)
  description = "Map of consumer name → workspace resource ID to link to AMPLS"
  default     = {}
}

variable "prometheus_workspace_id" {
  type        = string
  description = "Resource ID of the Azure Monitor Workspace (managed Prometheus) to link to AMPLS"
  default     = null
}
