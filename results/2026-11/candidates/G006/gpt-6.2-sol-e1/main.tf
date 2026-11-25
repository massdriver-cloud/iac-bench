data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

locals {
  # Azure Storage names are global and limited to 24 lowercase alphanumeric characters.
  storage_account_name = "st${substr(sha256(lower(data.azurerm_resource_group.app.id)), 0, 22)}"
}

resource "azurerm_storage_account" "app" {
  name                     = local.storage_account_name
  resource_group_name      = data.azurerm_resource_group.app.name
  location                 = data.azurerm_resource_group.app.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  cross_tenant_replication_enabled = false
  local_user_enabled               = false

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "app" {
  for_each = var.container_names

  name                  = each.value
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "app_blob_access" {
  for_each = azurerm_storage_container.app

  scope                = each.value.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${local.storage_account_name}-blob"
  resource_group_name = data.azurerm_resource_group.app.name
  location            = coalesce(var.private_endpoint_location, data.azurerm_resource_group.app.location)
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.app.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.blob_private_dns_zone_id]
  }

  tags = var.tags
}
