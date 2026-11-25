locals {
  is_prod             = var.environment == "prod"
  resource_group_name = "${var.application}-${var.environment}"

  # Storage account names: 3-24 chars, lowercase alphanumerics, globally unique.
  name_prefix          = substr("st${replace(var.application, "-", "")}${var.environment}", 0, 18)
  storage_account_name = "${local.name_prefix}${random_string.suffix.result}"

  # Production gets zone-redundant storage and longer recovery windows.
  replication_type = local.is_prod ? "ZRS" : "LRS"
  retention_days   = local.is_prod ? 30 : 7

  tags = merge(var.tags, {
    application = var.application
    environment = var.environment
    managed-by  = "opentofu"
  })
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    application = var.application
    environment = var.environment
  }
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Security baseline: Entra ID auth only, TLS 1.2+, no anonymous access,
  # no account keys / SAS, no SFTP local users.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  sftp_enabled                      = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = false

    delete_retention_policy {
      days = local.retention_days
    }

    container_delete_retention_policy {
      days = local.retention_days
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Versioning keeps old copies of overwritten blobs; expire them so costs don't grow unbounded.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-old-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.retention_days
      }
    }
  }
}

# The application's identity can read, write and delete blobs — nothing more.
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_principal_id
  principal_type       = "ServicePrincipal" # managed identities and app registrations alike
}

# Guard production data against accidental deletion of the whole account.
resource "azurerm_management_lock" "prod" {
  count = local.is_prod ? 1 : 0

  name       = "${azurerm_storage_account.this.name}-nodelete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Production application storage. Remove this lock deliberately before deleting."
}
