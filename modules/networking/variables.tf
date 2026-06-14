variable "resource_group_name" {
  type        = string
  description = "Resource group for all networking resources in this spoke"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "spoke_name" {
  type        = string
  description = "Short identifier for this spoke, used in peering names (e.g. 'obs-prod')"
}

variable "vnet_name" {
  type        = string
  description = "Name of the spoke virtual network"
}

variable "vnet_address_space" {
  type        = string
  description = "CIDR block for the spoke VNet (e.g. '10.100.0.0/23')"
}

variable "private_endpoints_subnet_cidr" {
  type        = string
  description = "CIDR for the private-endpoints subnet — hosts Key Vault PE and any future PEs (min /28)"
}

# ─────────────────────────────────────────
# Hub connectivity
# ─────────────────────────────────────────

variable "hub_vnet_id" {
  type        = string
  description = "Resource ID of the central hub VNet to peer with"
}

variable "hub_vnet_name" {
  type        = string
  description = "Name of the hub VNet (required only when manage_hub_peering = true)"
  default     = null
}

variable "hub_vnet_resource_group_name" {
  type        = string
  description = "Resource group of the hub VNet (required only when manage_hub_peering = true)"
  default     = null
}

variable "manage_hub_peering" {
  type        = bool
  description = <<-EOT
    When true, Terraform creates the hub→spoke peering in addition to the spoke→hub peering.
    Requires Contributor on the hub VNet's resource group.
    When false (default), raise a ticket to the network team to create the hub-side peering.
  EOT
  default     = false
}

variable "use_hub_gateway" {
  type        = bool
  description = "Set to true when the hub hosts a VPN or ExpressRoute gateway and spoke traffic should transit it"
  default     = false
}

variable "hub_firewall_private_ip" {
  type        = string
  description = "Private IP of the hub NVA/firewall. When set, a UDR forcing 0.0.0.0/0 through the firewall is created"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all networking resources"
  default     = {}
}
