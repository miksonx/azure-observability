# ─────────────────────────────────────────────────────────────────────────────
# 1. Networking — observability spoke VNet
#
# Creates the spoke VNet, private-endpoints subnet, NSG, and VNet peering
# to the central hub. The Key Vault private endpoint subnet ID is forwarded
# to the platform module so it does not need to be passed as a raw string.
# ─────────────────────────────────────────────────────────────────────────────

module "networking" {
  source = "./modules/networking"

  resource_group_name           = var.network_resource_group_name
  location                      = var.location
  spoke_name                    = "obs-${var.environment}"
  vnet_name                     = var.vnet_name
  vnet_address_space            = var.vnet_address_space
  private_endpoints_subnet_cidr = var.private_endpoints_subnet_cidr

  hub_vnet_id                  = var.hub_vnet_id
  hub_vnet_name                = var.hub_vnet_name
  hub_vnet_resource_group_name = var.hub_vnet_resource_group_name
  manage_hub_peering           = var.manage_hub_peering
  use_hub_gateway              = var.use_hub_gateway
  hub_firewall_private_ip      = var.hub_firewall_private_ip

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Platform — dedicated cluster + CMK + central workspace
#
# The private-endpoints subnet ID comes from the networking module so the
# Key Vault PE lands in the correct spoke subnet automatically.
# ─────────────────────────────────────────────────────────────────────────────

module "platform" {
  source = "./modules/log-analytics-cluster"

  resource_group_name             = var.platform_resource_group_name
  location                        = var.location
  cluster_name                    = var.cluster_name
  cluster_capacity_reservation_gb = var.cluster_capacity_reservation_gb
  platform_workspace_name         = var.platform_workspace_name
  retention_in_days               = var.default_retention_in_days

  key_vault_name                          = var.key_vault_name
  key_vault_key_name                      = var.key_vault_key_name
  key_expiry_days                         = var.key_expiry_days
  key_vault_public_network_access_enabled = var.key_vault_public_network_access_enabled
  key_vault_allowed_ips                   = var.key_vault_allowed_ips
  # Subnet ID now derived from networking module — no manual string needed
  key_vault_private_endpoint_subnet_id    = module.networking.private_endpoints_subnet_id
  private_dns_zone_resource_group_name    = var.private_dns_zone_resource_group_name

  tenant_id = var.tenant_id
  tags      = local.common_tags

  depends_on = [module.networking]
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Consumer workspaces — one per team, RBAC-isolated, separately billed
# ─────────────────────────────────────────────────────────────────────────────

module "consumers" {
  source   = "./modules/consumer-workspace"
  for_each = var.consumers

  consumer_name          = each.key
  location               = var.location
  cluster_id             = module.platform.cluster_id
  retention_in_days      = coalesce(each.value.retention_in_days, var.default_retention_in_days)
  workspace_contributors = each.value.workspace_contributors
  workspace_readers      = each.value.workspace_readers
  environment            = var.environment
  tags                   = merge(local.common_tags, each.value.extra_tags)
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. AMPLS registration
#
# Links the platform workspace, all consumer workspaces, and the Azure Monitor
# Workspace to the centrally-managed AMPLS so agent traffic flows privately
# through the hub's AMPLS private endpoint.
# ─────────────────────────────────────────────────────────────────────────────

module "ampls" {
  source = "./modules/ampls"

  ampls_name                = var.ampls_name
  ampls_resource_group_name = var.ampls_resource_group_name

  platform_workspace_name = var.platform_workspace_name
  platform_workspace_id   = module.platform.platform_workspace_id

  consumer_workspaces = {
    for k, v in module.consumers : k => v.workspace_id
  }

  prometheus_workspace_id = module.prometheus.monitor_workspace_id

  depends_on = [module.platform, module.consumers, module.prometheus]
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Azure Monitor Workspace (managed Prometheus) + Grafana RBAC
#
# Provisions the Prometheus-compatible metrics store and grants the external
# Grafana instance's managed identity query access to all workspaces.
# Created in the platform resource group (same billing scope as the cluster).
# ─────────────────────────────────────────────────────────────────────────────

module "prometheus" {
  source = "./modules/prometheus"

  resource_group_name           = var.platform_resource_group_name
  location                      = var.location
  monitor_workspace_name        = var.monitor_workspace_name
  public_network_access_enabled = false

  platform_workspace_id = module.platform.platform_workspace_id
  consumer_workspace_ids = {
    for k, v in module.consumers : k => v.workspace_id
  }

  grafana_managed_identity_principal_id = var.grafana_managed_identity_principal_id
  tags                                  = local.common_tags

  depends_on = [module.platform, module.consumers]
}
