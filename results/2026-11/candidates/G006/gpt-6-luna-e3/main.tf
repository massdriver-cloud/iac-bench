terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

data "azurerm_resource_group" "application" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "application" {
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.application.name
  location            = data.azurerm_resource_group.application.location

  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  access_tier                       = "Hot"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  local_user_enabled                = false
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    change_feed_retention_in_days = 7

    delete_retention_policy {
      days                     = 7
      permanent_delete_enabled = false
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = {
    managed_by = "opentofu"
    purpose    = "application-storage"
  }
}

resource "azurerm_storage_container" "application" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blob_data" {
  scope                = azurerm_storage_account.application.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
}
