data "azurerm_resource_group" "application" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "application" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.application.name
  location                 = data.azurerm_resource_group.application.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  is_hns_enabled                    = false

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = false

    delete_retention_policy {
      days                     = 30
      permanent_delete_enabled = false
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = merge(data.azurerm_resource_group.application.tags, var.tags)
}

# storage_account_id selects ARM management-plane container provisioning,
# avoiding an account-key dependency or a bootstrap data-plane role assignment.
resource "azurerm_storage_container" "application" {
  for_each              = var.containers
  name                  = each.value
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

# Data access only, limited to the containers this module provisions.
resource "azurerm_role_assignment" "application" {
  for_each                         = var.containers
  scope                            = azurerm_storage_container.application[each.key].resource_manager_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Do not expire current application data. Bound storage costs from historical
# versions only; the account's deletion retention still applies to deleted data.
resource "azurerm_storage_management_policy" "history" {
  storage_account_id = azurerm_storage_account.application.id

  rule {
    name    = "expire-old-versions"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      version {
        delete_after_days_since_creation = 90
      }
    }
  }
}
