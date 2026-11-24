data "azurerm_resource_group" "application" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "application" {
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.application.name
  location            = data.azurerm_resource_group.application.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false

  # Identity is the access boundary. This works without assuming either an
  # AKS or App Service VNet topology; it does not permit anonymous blob access.
  public_network_access_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "application" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blob_access" {
  for_each = azurerm_storage_container.application

  scope                            = each.value.resource_manager_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Keep old versions from accumulating indefinitely, without expiring current
# application data. Version retention is not a substitute for a backup policy.
resource "azurerm_storage_management_policy" "versions" {
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
      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }
}
