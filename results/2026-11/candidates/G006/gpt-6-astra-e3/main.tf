data "azurerm_resource_group" "application" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "application" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.application.name
  location                 = data.azurerm_resource_group.application.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days                     = 30
      permanent_delete_enabled = false
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action             = var.network_restrictions == null ? "Allow" : "Deny"
    bypass                     = ["None"]
    ip_rules                   = var.network_restrictions == null ? [] : var.network_restrictions.ip_rules
    virtual_network_subnet_ids = var.network_restrictions == null ? [] : var.network_restrictions.subnet_ids
  }

  tags = merge(var.tags, { managed_by = "OpenTofu" })

  lifecycle {
    prevent_destroy = true
  }
}

# Account IDs select the ARM-based container API; no account keys are needed.
resource "azurerm_storage_container" "application" {
  for_each              = var.container_names
  name                  = each.value
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blobs" {
  for_each             = azurerm_storage_container.application
  scope                = each.value.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
  # The ID is provided by the caller; no tenant-wide directory read is needed.
  skip_service_principal_aad_check = true
}

# Bound the storage cost of recovery history; never expire current blobs.
resource "azurerm_storage_management_policy" "history" {
  storage_account_id = azurerm_storage_account.application.id
  rule {
    name    = "expire-old-recovery-history"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      version {
        delete_after_days_since_creation = 90
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }
}
