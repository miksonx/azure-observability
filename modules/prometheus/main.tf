# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor Workspace (managed Prometheus)
#
# Provides a Prometheus-compatible remote-write endpoint for metrics ingestion
# and a PromQL query endpoint that Grafana consumes as a Prometheus data source.
#
# Relationship to Log Analytics:
#   - Log Analytics workspaces store logs (KQL queries).
#   - Azure Monitor Workspace stores time-series metrics (PromQL queries).
#   - Both are exposed to Grafana via separate data sources.
#   - Both are linked to the same AMPLS for private network access.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_workspace" "main" {
  name                          = var.monitor_workspace_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  public_network_access_enabled = var.public_network_access_enabled

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Prometheus scraping Data Collection Rule (DCR)
#
# This DCR configures the Azure Monitor Agent to forward Prometheus metrics
# from the host to the Azure Monitor Workspace.
#
# Consumer teams link their AKS clusters / VMs to this DCR by creating a
# Data Collection Rule Association (DCRA) — example:
#
#   resource "azurerm_monitor_data_collection_rule_association" "aks" {
#     name                    = "dcra-aks-${team_name}"
#     target_resource_id      = azurerm_kubernetes_cluster.main.id
#     data_collection_rule_id = "<prometheus_dcr_id output>"
#   }
#
# kind = "Linux" targets Linux-based AKS node pools (most common).
# For Windows workloads, provision a separate DCR with kind = "Windows".
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                = "dcr-prometheus-${var.monitor_workspace_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  description         = "Prometheus metrics scraping — associate with AKS clusters to enable managed Prometheus"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.main.id
      name               = "MonitoringAccount"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
      # Empty label_include_filter = forward all metric labels
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# RBAC — Grafana managed identity
#
# The Grafana instance (provided by another team) uses its managed identity
# to query both the Azure Monitor Workspace (Prometheus) and Log Analytics
# workspaces (logs) without storing credentials.
#
# Monitoring Reader on AMW   → enables PromQL queries via Grafana Prometheus DS
# Log Analytics Reader on each workspace → enables KQL queries via Grafana
#                                           Azure Monitor DS
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_role_assignment" "grafana_amw_reader" {
  scope                = azurerm_monitor_workspace.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = var.grafana_managed_identity_principal_id
  description          = "Grafana managed identity — Prometheus query access"
}

resource "azurerm_role_assignment" "grafana_platform_workspace_reader" {
  scope                = var.platform_workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = var.grafana_managed_identity_principal_id
  description          = "Grafana managed identity — platform workspace log query access"
}

resource "azurerm_role_assignment" "grafana_consumer_workspace_reader" {
  for_each = var.consumer_workspace_ids

  scope                = each.value
  role_definition_name = "Log Analytics Reader"
  principal_id         = var.grafana_managed_identity_principal_id
  description          = "Grafana managed identity — ${each.key} workspace log query access"
}
