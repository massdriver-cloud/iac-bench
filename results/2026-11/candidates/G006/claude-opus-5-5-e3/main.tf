locals {
  is_production = var.environment == "prod"

  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")

  env_short = {
    dev     = "d"
    test    = "t"
    staging = "s"
    prod    = "p"
  }[var.environment]

  # Storage account names: 3-24 chars, lowercase alphanumeric, globally unique.
  # "st" + up to 14 chars of app name + 1 char env + 6 random chars <= 23.
  app_compact          = replace(var.application_name, "-", "")
  storage_account_name = "st${substr(local.app_compact, 0, min(14, length(local.app_compact)))}${local.env_short}${random_string.suffix.result}"

  # Production data is kept on zone-redundant storage and protected longer.
  replication_type     = local.is_production ? "ZRS" : "LRS"
  soft_delete_days     = local.is_production ? 30 : 7
  old_version_ttl_days = local.is_production ? 90 : 30

  tags = merge(var.tags, {
    application = var.application_name
    environment = var.environment
    managed_by  = "opentofu"
    module      = "app-storage"
  })
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true

  keepers = {
    application = var.application_name
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

  # Transport and access hardening. Applications authenticate with their
  # Entra ID identity; account keys and anonymous access are turned off.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  sftp_enabled                      = false
  is_hns_enabled                    = false

  # Reachable from AKS / App Service over the public endpoint, but only with
  # Entra ID-authenticated requests.
  public_network_access_enabled = true

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

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

# Keep versioning from growing storage costs without bound.
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
        delete_after_days_since_creation = local.old_version_ttl_days
      }
      snapshot {
        delete_after_days_since_creation_greater_than = local.old_version_ttl_days
      }
    }
  }
}

# The application's identity can read, write and delete blobs (and request
# user-delegation SAS tokens for browser uploads/downloads).
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Guard production data against accidental deletion of the account.
resource "azurerm_management_lock" "prod" {
  count = local.is_production ? 1 : 0

  name       = "${local.storage_account_name}-no-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Production application storage. Remove this lock deliberately before deleting the account."
}
