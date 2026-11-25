locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.application}-${var.environment}")

  is_production = contains(["prod", "production", "prd"], var.environment)

  # Production data survives a zonal outage; non-production keeps costs low.
  replication_type = local.is_production ? "ZRS" : "LRS"

  # How long deleted / overwritten data can be recovered.
  soft_delete_days      = local.is_production ? 30 : 7
  old_version_keep_days = local.is_production ? 90 : 30

  # Storage account names: 3-24 lowercase alphanumerics, globally unique.
  name_app = substr(replace(var.application, "-", ""), 0, 12)
  name_env = substr(var.environment, 0, 4)

  tags = merge(var.tags, {
    application = var.application
    environment = var.environment
    managed-by  = "opentofu"
  })
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "this" {
  name                = "st${local.name_app}${local.name_env}${random_string.suffix.result}"
  resource_group_name = local.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Transport and authentication: Entra ID only, TLS 1.2+, nothing anonymous.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  infrastructure_encryption_enabled = true

  # Apps on AKS / App Service reach the account over its public endpoint;
  # access is controlled by Entra ID identity, not by network location.
  public_network_access_enabled = true

  blob_properties {
    # Overwritten or deleted files can be recovered.
    versioning_enabled = true

    delete_retention_policy {
      days = local.soft_delete_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
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

# Keep previous versions only for a bounded time so versioning doesn't grow
# storage costs without limit.
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
        delete_after_days_since_creation = local.old_version_keep_days
      }
    }
  }
}

# The application's own identity gets read/write/delete on blob data.
resource "azurerm_role_assignment" "application_blob" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Production accounts cannot be deleted by accident.
resource "azurerm_management_lock" "this" {
  count = local.is_production ? 1 : 0

  name       = "do-not-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Holds production application data. Remove this lock deliberately before deleting the account."
}
