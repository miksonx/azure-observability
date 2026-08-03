terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }

  # Configure backend via CLI flags or a backend config file:
  #   terraform init -backend-config="backend.conf"
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# Grafana provider — only makes API calls when grafana_datasources.tf resources
# have count > 0 (i.e. when grafana_endpoint and grafana_service_account_token
# are both set). The coalesce fallbacks prevent provider init errors when
# Grafana integration is disabled.
provider "grafana" {
  url  = coalesce(var.grafana_endpoint, "http://localhost:3000")
  auth = coalesce(var.grafana_service_account_token, "disabled")
}
