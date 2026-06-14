variable "consumer_name" {
  type        = string
  description = "Unique consumer identifier (2–20 lowercase alphanumerics / hyphens) — used in resource names"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.consumer_name))
    error_message = "consumer_name must be 2–20 lowercase alphanumeric characters or hyphens."
  }
}

variable "location" {
  type        = string
  description = "Azure region for consumer resources (should match the cluster region)"
}

variable "cluster_id" {
  type        = string
  description = "Resource ID of the shared dedicated Log Analytics cluster to link this workspace to"
}

variable "retention_in_days" {
  type        = number
  description = "Data retention period in days for this consumer workspace (30–730)"
  default     = 90

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "Retention must be between 30 and 730 days."
  }
}

variable "workspace_contributors" {
  type        = list(string)
  description = "AAD object IDs (users, groups, or service principals) granted Log Analytics Contributor on this workspace"
  default     = []
}

variable "workspace_readers" {
  type        = list(string)
  description = "AAD object IDs granted Log Analytics Reader on this workspace"
  default     = []
}

variable "environment" {
  type        = string
  description = "Environment label (e.g., prod)"
  default     = "prod"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources in this consumer module"
  default     = {}
}
