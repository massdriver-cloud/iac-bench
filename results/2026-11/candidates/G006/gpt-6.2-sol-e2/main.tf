data "azurerm_resource_group" "application" {
  name = var.resource_group_name
}

locals {
  # Account names are globally scoped, lowercase alphanumeric, and at most 24 characters.
  # Use the resource group's ARM ID to distinguish identical group names in different subscriptions.
  group_slug   = replace(lower(data.azurerm_resource_group.application.name), "/[^a-z0-9]/", "")
  group_hash   = substr(sha256(lower(data.azurerm_resource_group.application.id)), 0, 16)
  account_name = "st${substr(local.group_slug, 0, 6)}${local.group_hash}"
}

resource "azurerm_storage_account" "application" {
  name                = local.account_name
  resource_group_name = data.azurerm_resource_group.application.name
  location            = data.azurerm_resource_group.application.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  local_user_enabled               = false
  cross_tenant_replication_enabled = false
  public_network_access_enabled    = var.private_endpoint == null

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
  for_each = var.container_names

  name                  = each.key
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blob_access" {
  for_each = azurerm_storage_container.application

  scope                = each.value.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_storage_management_policy" "blob_versions" {
  storage_account_id = azurerm_storage_account.application.id

  rule {
    name    = "expire-old-blob-versions"
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

resource "azurerm_private_endpoint" "blob" {
  count = var.private_endpoint == null ? 0 : 1

  name                = "${azurerm_storage_account.application.name}-blob-pe"
  resource_group_name = data.azurerm_resource_group.application.name
  location            = coalesce(var.private_endpoint.location, data.azurerm_resource_group.application.location)
  subnet_id           = var.private_endpoint.subnet_id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.application.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.private_endpoint.private_dns_zone_id]
  }

  tags = var.tags
}
