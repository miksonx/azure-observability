locals {
  consumer_tags = merge(var.tags, {
    consumer    = var.consumer_name
    environment = var.environment
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Consumer resource group
# One RG per consumer enables:
#   - Cost allocation / chargeback via Azure Cost Management (filter by RG)
#   - Independent RBAC scope — consumer admins can be given Contributor on
#     their own RG without touching the shared platform
#   - Isolation: consumer teams can request budget alerts on their own RG
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "consumer" {
  name     = "rg-observability-${var.consumer_name}-${var.environment}"
  location = var.location
  tags     = local.consumer_tags
}

resource "azurerm_management_lock" "consumer_rg" {
  name       = "observability-lock"
  scope      = azurerm_resource_group.consumer.id
  lock_level = "CanNotDelete"
  notes      = "Observability workspace for ${var.consumer_name} — managed by platform team"
}

# ─────────────────────────────────────────────────────────────────────────────
# Consumer Log Analytics workspace
#
# SKU must be PerGB2018; the dedicated cluster overrides ingestion billing
# (you are charged at cluster commitment tier, not per-GB per workspace).
# Each workspace retains its own query scope and RBAC boundary, so consumers
# cannot read each other's data even though they share the cluster.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "consumer" {
  name                = "law-${var.consumer_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.consumer.name
  location            = azurerm_resource_group.consumer.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days

  tags = local.consumer_tags
}

# Link this workspace to the shared dedicated cluster.
# After linking: all data written to this workspace is encrypted with
# the cluster's CMK and counted against the cluster commitment tier.
resource "azurerm_log_analytics_linked_service" "cluster" {
  resource_group_name = azurerm_resource_group.consumer.name
  workspace_id        = azurerm_log_analytics_workspace.consumer.id
  resource_id         = var.cluster_id
}

# ─────────────────────────────────────────────────────────────────────────────
# RBAC — workspace-scoped access control
#
# Log Analytics Contributor: can create/manage workspaces, solutions, and
#   storage accounts linked to the workspace. Suitable for DevOps pipelines
#   and engineers who need to configure data collection.
#
# Log Analytics Reader: read-only query access. Suitable for developers,
#   product teams, and monitoring dashboards.
#
# Grant at workspace scope (not resource group) so consumers cannot affect
# other resources in their RG through Log Analytics permissions.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_role_assignment" "contributor" {
  for_each = toset(var.workspace_contributors)

  scope                = azurerm_log_analytics_workspace.consumer.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "reader" {
  for_each = toset(var.workspace_readers)

  scope                = azurerm_log_analytics_workspace.consumer.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = each.value
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic settings on the consumer workspace
# Sends workspace audit events (query activity, configuration changes) to
# itself for compliance traceability within the consumer's own scope.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "workspace_audit" {
  name                       = "diag-${azurerm_log_analytics_workspace.consumer.name}"
  target_resource_id         = azurerm_log_analytics_workspace.consumer.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.consumer.id

  enabled_log {
    category = "Audit"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [azurerm_log_analytics_linked_service.cluster]
}
