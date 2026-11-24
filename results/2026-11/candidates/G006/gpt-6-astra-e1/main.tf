data "azurerm_resource_group" "application" {
  name = var.resource_group_name
}

locals {
  tags = merge(data.azurerm_resource_group.application.tags, var.tags)
}

resource "azurerm_storage_account" "application" {
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.application.name
  location            = data.azurerm_resource_group.application.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = var.private_endpoint == null
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  # Block accidental NFS/SFTP or hierarchical namespace use: this is object storage.
  is_hns_enabled = false
  nfsv3_enabled  = false
  sftp_enabled   = false

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
    default_action = var.private_endpoint == null ? "Allow" : "Deny"
    bypass         = ["None"]
  }

  tags = local.tags

  # Deleting a storage account is not covered by blob soft deletion.
  # Removal/replacement requires an explicit code change and migration review.
  lifecycle {
    prevent_destroy = true
  }
}

# storage_account_id uses the ARM management API, not shared-key data-plane access.
# Provisioning therefore also works when the public data endpoint is disabled.
resource "azurerm_storage_container" "application" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application" {
  for_each = var.containers

  scope                            = azurerm_storage_container.application[each.key].resource_manager_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Keep current application data indefinitely; limit the cost of older versions.
resource "azurerm_storage_management_policy" "history" {
  storage_account_id = azurerm_storage_account.application.id

  rule {
    name    = "expire-old-history"
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

resource "azurerm_private_endpoint" "blob" {
  count = var.private_endpoint == null ? 0 : 1

  name                = "${var.storage_account_name}-blob"
  location            = data.azurerm_resource_group.application.location
  resource_group_name = data.azurerm_resource_group.application.name
  subnet_id           = var.private_endpoint.subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.application.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.private_endpoint.private_dns_zone_id]
  }
}
