# ─────────────────────────────────────────────────────────────────────────────
# Reference the centrally-managed AMPLS
#
# AMPLS is provided by the central platform / networking team.
# This module registers this deployment's workspaces as scoped services,
# which routes all Azure Monitor agent traffic through the AMPLS private
# endpoint rather than the public internet.
#
# Prerequisites:
#   - The deploying SP must have Contributor on var.ampls_resource_group_name
#   - The AMPLS private endpoint must resolve via hub DNS (Azure Private DNS
#     zones linked to the hub VNet and propagated to spoke via peering)
#
# Private DNS zones required (managed centrally):
#   - privatelink.ods.opinsights.azure.com
#   - privatelink.oms.opinsights.azure.com
#   - privatelink.agentsvc.azure-automation.net
#   - privatelink.blob.core.windows.net          (for agent storage)
#   - privatelink.monitor.azure.com              (for Azure Monitor Workspace)
# ─────────────────────────────────────────────────────────────────────────────

data "azurerm_monitor_private_link_scope" "central" {
  name                = var.ampls_name
  resource_group_name = var.ampls_resource_group_name
}

# ─────────────────────────────────────────────────────────────────────────────
# Register the central platform workspace
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_private_link_scoped_service" "platform_workspace" {
  name                = "ampls-svc-${var.platform_workspace_name}"
  resource_group_name = var.ampls_resource_group_name
  scope_name          = data.azurerm_monitor_private_link_scope.central.name
  linked_resource_id  = var.platform_workspace_id
}

# ─────────────────────────────────────────────────────────────────────────────
# Register each consumer workspace
#
# All workspaces linked to AMPLS share the same private endpoint — agents
# resolve all workspace hostnames to the AMPLS PE IP. Each workspace remains
# independently RBAC-controlled; AMPLS only affects the network path.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_private_link_scoped_service" "consumer_workspaces" {
  for_each = var.consumer_workspaces

  name                = "ampls-svc-${each.key}"
  resource_group_name = var.ampls_resource_group_name
  scope_name          = data.azurerm_monitor_private_link_scope.central.name
  linked_resource_id  = each.value
}

# ─────────────────────────────────────────────────────────────────────────────
# Register the Azure Monitor Workspace (managed Prometheus)
#
# Linking the AMW to AMPLS routes Prometheus remote-write from agents through
# the private endpoint, and locks down the Prometheus query endpoint so it is
# only reachable via AMPLS-connected networks.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_private_link_scoped_service" "prometheus_workspace" {
  count = var.prometheus_workspace_id != null ? 1 : 0

  name                = "ampls-svc-prometheus"
  resource_group_name = var.ampls_resource_group_name
  scope_name          = data.azurerm_monitor_private_link_scope.central.name
  linked_resource_id  = var.prometheus_workspace_id
}
