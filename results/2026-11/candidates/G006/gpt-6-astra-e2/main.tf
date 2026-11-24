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

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  cross_tenant_replication_enabled = false
  public_network_access_enabled    = true
  is_hns_enabled                   = false
  sftp_enabled                     = false
  local_user_enabled               = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action             = var.network_access == null ? "Allow" : "Deny"
    bypass                     = ["None"]
    ip_rules                   = var.network_access == null ? [] : var.network_access.ip_rules
    virtual_network_subnet_ids = var.network_access == null ? [] : var.network_access.subnet_ids
  }

  tags = merge(data.azurerm_resource_group.application.tags, var.tags)

  # Require a deliberate source change before account deletion/replacement.
  lifecycle {
    prevent_destroy = true
  }
}

# storage_account_id uses the ARM API: deployment does not require account keys
# or Blob data-plane privileges, even when the firewall is enabled.
resource "azurerm_storage_container" "application" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blob_access" {
  for_each = azurerm_storage_container.application

  scope                            = each.value.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Never expire current application data. Bound the accumulation of old
# versions and snapshots; soft-deleted data can incur additional retention.
resource "azurerm_storage_management_policy" "recovery_cleanup" {
  storage_account_id = azurerm_storage_account.application.id

  rule {
    name    = "expire-old-versions-and-snapshots"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = 30
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
}
