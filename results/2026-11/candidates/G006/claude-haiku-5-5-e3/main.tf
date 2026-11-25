locals {
  # Convention: each application has one resource group per environment,
  # named <app>-<environment>, e.g. orders-staging. Storage lives there.
  resource_group_name = "${var.app_name}-${var.environment}"

  # Storage account names: 3-24 chars, lowercase letters and digits, globally unique.
  # st + app (hyphens removed, max 11) + env (3) + random (6) = max 22 chars.
  app_compact = replace(var.app_name, "-", "")
  env_short   = { dev = "dev", staging = "stg", prod = "prd" }[var.environment]

  # Redundancy: prod is geo-redundant for regional disaster recovery; non-prod stays local.
  replication_type = { dev = "LRS", staging = "LRS", prod = "GRS" }[var.environment]

  is_prod = var.environment == "prod"

  # Workload profiles. Each one fixes the containers, tiering and retention.
  workload_profiles = {
    uploads = {
      containers                 = ["uploads"]
      tier_to_cool_after_days    = 90
      delete_after_days          = null # user files are never auto-deleted
      blob_delete_retention_days = 30
    }
    media = {
      containers                 = ["images", "videos"]
      tier_to_cool_after_days    = 30
      delete_after_days          = null
      blob_delete_retention_days = 14
    }
    exports = {
      containers                 = ["reports"]
      tier_to_cool_after_days    = 30
      delete_after_days          = 365 # generated output can be regenerated
      blob_delete_retention_days = 7
    }
  }

  profile = local.workload_profiles[var.workload]

  tags = merge(var.tags, {
    app         = var.app_name
    environment = var.environment
    workload    = var.workload
    managed-by  = "opentofu"
  })
}

data "azurerm_resource_group" "app" {
  name = local.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "this" {
  name                = "st${local.app_compact}${local.env_short}${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type

  # Identity-based access only: no account keys, no SAS signed with keys,
  # no local SFTP/NFS users, no anonymous access, no cross-tenant replication.
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  local_user_enabled               = false

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  infrastructure_encryption_enabled = true
  sftp_enabled                      = false
  nfsv3_enabled                     = false
  is_hns_enabled                    = false

  # Deny by default. Entra-authorized requests from trusted Azure services still work.
  public_network_access_enabled = true
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = local.profile.blob_delete_retention_days
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# The application's own identity gets data access through Entra ID RBAC.
resource "azurerm_role_assignment" "app_data" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_object_id
}

resource "azurerm_storage_container" "this" {
  for_each = toset(local.profile.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "${var.workload}-lifecycle"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = local.profile.tier_to_cool_after_days
        delete_after_days_since_modification_greater_than       = local.profile.delete_after_days
      }
    }
  }
}

# Production storage cannot be deleted by accident. Remove the lock deliberately first.
resource "azurerm_management_lock" "prod_no_delete" {
  count = local.is_prod ? 1 : 0

  name       = "${azurerm_storage_account.this.name}-no-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Production application storage. Remove this lock before decommissioning."
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "${azurerm_storage_account.this.name}-blob-diag"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}
