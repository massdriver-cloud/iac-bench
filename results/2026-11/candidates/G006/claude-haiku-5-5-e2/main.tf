locals {
  # Convention: every application has <app>-<env> resource group per environment.
  resource_group_name = "${var.app_name}-${var.environment}"

  # Replication: production gets zone redundancy; everything else is LRS to keep cost down.
  replication_type = var.environment == "prod" ? "ZRS" : "LRS"

  # Firewall: deny-by-default only when the team has named a network to allow.
  network_restricted = length(var.allowed_ip_ranges) > 0 || length(var.allowed_subnet_ids) > 0

  common_tags = merge(var.tags, {
    application = var.app_name
    environment = var.environment
    managed-by  = "opentofu"
  })
}

data "azurerm_resource_group" "app" {
  name = local.resource_group_name
}

data "azurerm_client_config" "current" {}

# Storage account names are globally unique, 3-24 lowercase alphanumerics.
# app (<=10) + env (<=7) + suffix (6) <= 23 characters, always valid.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_storage_account" "this" {
  name                = "${var.app_name}${var.environment}${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Security baseline
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false # Entra ID (RBAC) only; no account keys or SAS keys
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false # no anonymous blob access, ever
  cross_tenant_replication_enabled = false
  sftp_enabled                     = false
  nfsv3_enabled                    = false
  local_user_enabled               = false
  public_network_access_enabled    = true # firewall below governs access

  network_rules {
    default_action             = local.network_restricted ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  # Recovery: accidental overwrites and deletes are recoverable.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Cost control: move cold blobs to Cool, and clean up old versions.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "tier-and-expire-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }

      version {
        change_tier_to_cool_after_days_since_creation = 30
        delete_after_days_since_creation              = 90
      }
    }
  }
}

# The application's own identity gets data-plane access. Nobody else is granted
# standing access by this module; humans get access through their own roles.
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_principal_id
  principal_type       = "ServicePrincipal"
}
