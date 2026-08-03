# ─────────────────────────────────────────────────────────────────────────────
# Resource group
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "network" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_management_lock" "network_rg" {
  name       = "${var.resource_group_name}-lock"
  scope      = azurerm_resource_group.network.id
  lock_level = "CanNotDelete"
  notes      = "Observability spoke networking — managed by platform team"
}

# ─────────────────────────────────────────────────────────────────────────────
# Spoke VNet
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "spoke" {
  name                = var.vnet_name
  address_space       = [var.vnet_address_space]
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Private-endpoints subnet
# Hosts: Key Vault PE, Azure Monitor Workspace DCE PE (if enabled), future PEs.
# Network policies are disabled — required for private endpoint NICs.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.network.name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = [var.private_endpoints_subnet_cidr]
  private_endpoint_network_policies = "Disabled"
}

# NSG: attached to subnet; no custom inbound rules because private endpoint
# traffic is controlled by the PE's NIC, not the NSG on the parent subnet.
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-snet-private-endpoints"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = var.tags

  security_rule {
    name                       = "deny-internet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Route table (optional — only when hub hosts an NVA / Azure Firewall)
#
# Forces all subnet traffic through the hub firewall for inspection.
# BGP propagation left enabled so hub-advertised routes (e.g. on-prem) are
# learned; the explicit 0.0.0.0/0 UDR overrides the default internet route.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_route_table" "private_endpoints" {
  count = var.hub_firewall_private_ip != null ? 1 : 0

  name                          = "rt-snet-private-endpoints"
  resource_group_name           = azurerm_resource_group.network.name
  location                      = azurerm_resource_group.network.location
  disable_bgp_route_propagation = false
  tags                          = var.tags
}

resource "azurerm_route" "default_to_firewall" {
  count = var.hub_firewall_private_ip != null ? 1 : 0

  name                   = "default-via-hub-firewall"
  resource_group_name    = azurerm_resource_group.network.name
  route_table_name       = azurerm_route_table.private_endpoints[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.hub_firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "private_endpoints" {
  count = var.hub_firewall_private_ip != null ? 1 : 0

  subnet_id      = azurerm_subnet.private_endpoints.id
  route_table_id = azurerm_route_table.private_endpoints[0].id
}

# ─────────────────────────────────────────────────────────────────────────────
# VNet peering: Spoke → Hub
#
# allow_forwarded_traffic = true  — accept routes advertised by the hub (on-prem,
#                                   other spokes via hub NVA)
# use_remote_gateways     = true  — only when the hub hosts a VPN/ER gateway and
#                                   gateway_transit is enabled on the hub side
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${var.spoke_name}-to-hub"
  resource_group_name          = azurerm_resource_group.network.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_hub_gateway
}

# ─────────────────────────────────────────────────────────────────────────────
# VNet peering: Hub → Spoke (optional)
#
# Set manage_hub_peering = true when the deploying SP has Contributor on the
# hub VNet's resource group. Otherwise, raise a ticket to the network team
# with the spoke VNet ID from the output and ask them to create:
#
#   allow_forwarded_traffic = true
#   allow_gateway_transit   = true   (if hub has a gateway)
#   use_remote_gateways     = false
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count = var.manage_hub_peering ? 1 : 0

  name                         = "peer-hub-to-${var.spoke_name}"
  resource_group_name          = var.hub_vnet_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}
