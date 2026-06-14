data "azurerm_client_config" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# Platform resource group
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "platform" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Prevent accidental deletion by privileged operators
resource "azurerm_management_lock" "platform_rg" {
  name       = "${var.resource_group_name}-lock"
  scope      = azurerm_resource_group.platform.id
  lock_level = "CanNotDelete"
  notes      = "Shared observability platform — deletion must be intentional"
}

# ─────────────────────────────────────────────────────────────────────────────
# Managed identity for the Log Analytics dedicated cluster
# The cluster uses this identity to unwrap the CMK from Key Vault.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${var.cluster_name}-identity"
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault — Customer-Managed Key (CMK)
# SKU: Premium (HSM-backed keys, required for regulatory compliance)
# RBAC auth: yes — classic access policies are discouraged at scale
# Purge protection: mandatory when used as a CMK store
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  tenant_id           = var.tenant_id
  sku_name            = "premium"

  enable_rbac_authorization       = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 90
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false

  public_network_access_enabled = var.key_vault_public_network_access_enabled

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = var.key_vault_allowed_ips
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# RBAC for Key Vault
# ─────────────────────────────────────────────────────────────────────────────

# The Terraform service principal / deployer must be Key Vault Administrator
# to create and rotate keys. Scope to the vault (not subscription) for least privilege.
resource "azurerm_role_assignment" "kv_admin_deployer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The cluster managed identity needs this built-in role to wrap/unwrap CMK
resource "azurerm_role_assignment" "kv_crypto_cluster" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

# ─────────────────────────────────────────────────────────────────────────────
# CMK key with automatic rotation
# Key type: RSA-HSM 4096 (Premium SKU enables HSM-backed keys)
# Rotation: 90 days before expiry → satisfies most enterprise key hygiene policies
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_key_vault_key" "cmk" {
  name         = var.key_vault_key_name
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  rotation_policy {
    automatic {
      # Trigger rotation 90 days before the current key version expires
      time_before_expiry = "P90D"
    }
    expire_after         = "P${var.key_expiry_days}D"
    notify_before_expiry = "P30D"
  }

  # Role assignment for the deployer must exist before key creation can succeed
  depends_on = [azurerm_role_assignment.kv_admin_deployer]

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault private endpoint (optional — enabled when subnet ID is provided)
#
# Enterprise pattern: Key Vault is only reachable via private network.
# Requires: a private DNS zone (privatelink.vaultcore.azure.net) already linked
# to the VNet, and the Terraform runner on the same private network.
# ─────────────────────────────────────────────────────────────────────────────

data "azurerm_private_dns_zone" "key_vault" {
  count               = var.key_vault_private_endpoint_subnet_id != null ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.private_dns_zone_resource_group_name
}

resource "azurerm_private_endpoint" "key_vault" {
  count               = var.key_vault_private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-${var.key_vault_name}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  subnet_id           = var.key_vault_private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.key_vault[0].id]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Log Analytics Dedicated Cluster
#
# The cluster provides:
#   - A single billing commitment shared across all linked workspaces
#   - CMK encryption applied cluster-wide (all linked workspaces inherit it)
#   - Data is encrypted at rest with the CMK before being written to storage
#
# NOTE: Cluster provisioning typically takes 10–15 minutes.
# The CMK attachment depends on the cluster reaching "Succeeded" state.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  size_gb             = var.cluster_capacity_reservation_gb

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  tags = var.tags
}

# Attach CMK to the dedicated cluster.
# Uses versionless key URI so encryption continues transparently after key rotation.
resource "azurerm_log_analytics_cluster_customer_managed_key" "main" {
  log_analytics_cluster_id = azurerm_log_analytics_cluster.main.id
  key_vault_key_id         = azurerm_key_vault_key.cmk.versionless_id

  depends_on = [azurerm_role_assignment.kv_crypto_cluster]
}

# ─────────────────────────────────────────────────────────────────────────────
# Platform (central) workspace
# Used for: infrastructure metrics, platform telemetry, Azure Activity Logs,
#           cross-consumer alerting, and security / audit data.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "platform" {
  name                = var.platform_workspace_name
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days

  tags = var.tags
}

# Link the platform workspace to the dedicated cluster so it participates
# in the shared commitment and inherits CMK encryption
resource "azurerm_log_analytics_linked_service" "platform_cluster" {
  resource_group_name = azurerm_resource_group.platform.name
  workspace_id        = azurerm_log_analytics_workspace.platform.id
  resource_id         = azurerm_log_analytics_cluster.main.id

  # Cluster CMK must be configured before workspaces are linked
  depends_on = [azurerm_log_analytics_cluster_customer_managed_key.main]
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic settings on the platform workspace itself
# Sends workspace audit events back into the same workspace for traceability.
# In large deployments consider a dedicated security / SIEM workspace instead.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "platform_workspace_audit" {
  name                       = "diag-${var.platform_workspace_name}"
  target_resource_id         = azurerm_log_analytics_workspace.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  enabled_log {
    category = "Audit"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [azurerm_log_analytics_linked_service.platform_cluster]
}
