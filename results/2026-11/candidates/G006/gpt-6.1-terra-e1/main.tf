resource "azurerm_storage_account" "app" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  cross_tenant_replication_enabled = false
  public_network_access_enabled    = true
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

  dynamic "network_rules" {
    for_each = length(var.allowed_subnet_ids) + length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["None"]
      virtual_network_subnet_ids = var.allowed_subnet_ids
      ip_rules                   = var.allowed_ip_ranges
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "app" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blob_data" {
  scope                = azurerm_storage_container.app.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
}
