########################################
# Derived settings
########################################

locals {
  is_production       = contains(["prod", "production"], var.environment)
  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")

  # Storage account names: 3-24 chars, lowercase letters and digits only, globally unique.
  # "st" + <app><env> (truncated to 17) + 5-char random suffix  => always <= 24 characters.
  name_body            = substr(replace("${var.application_name}${var.environment}", "-", ""), 0, 17)
  storage_account_name = "st${local.name_body}${random_string.suffix.result}"

  # Production gets geo-redundancy and longer soft-delete retention; everything else stays cheap.
  replication_type     = coalesce(var.replication_type, local.is_production ? "GRS" : "LRS")
  soft_delete_days     = local.is_production ? 30 : 7
  version_cleanup_days = local.soft_delete_days

  restrict_network    = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0
  enable_cool_tiering = var.cool_tier_after_days > 0

  tags = merge(
    {
      application = var.application_name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )
}

########################################
# The application's existing resource group
########################################

data "azurerm_resource_group" "app" {
  name = local.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

########################################
# Storage account
########################################

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Entra ID only: no account keys, no key-derived SAS tokens. Apps authenticate
  # with their managed identity (DefaultAzureCredential) and RBAC.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # Transport and exposure hardening.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  network_rules {
    default_action             = local.restrict_network ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  blob_properties {
    # Versioning + soft delete protect user data from accidental overwrite/deletion.
    versioning_enabled = true

    delete_retention_policy {
      days = local.soft_delete_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }
  }

  tags = local.tags

  lifecycle {
    # The name embeds a random suffix; never replace an account that holds
    # application data because of a naming change.
    ignore_changes = [name]
  }
}

########################################
# Containers
########################################

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

########################################
# Data access for the application's identity
########################################

resource "azurerm_role_assignment" "app" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = var.app_identity_role
  principal_id         = var.app_identity_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Grants the ${var.application_name} (${var.environment}) application identity data access to its storage account."
}

########################################
# Lifecycle management: cheaper tier for stale files, prune old versions
########################################

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = local.enable_cool_tiering ? [1] : []

    content {
      name    = "tier-stale-files-to-cool"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than = var.cool_tier_after_days
        }
      }
    }
  }

  rule {
    name    = "prune-old-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.version_cleanup_days
      }
    }
  }
}
