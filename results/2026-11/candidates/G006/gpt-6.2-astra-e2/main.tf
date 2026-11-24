terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

locals {
  # Include subscription and environment (via the RG ID) in the global name.
  stem = substr(replace(lower(var.resource_group_name), "/[^a-z0-9]/", ""), 0, 10)
  name = "st${local.stem}${substr(sha256(lower(data.azurerm_resource_group.app.id)), 0, 12)}"
}

resource "azurerm_storage_account" "app" {
  name                     = local.name
  resource_group_name      = data.azurerm_resource_group.app.name
  location                 = data.azurerm_resource_group.app.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  local_user_enabled              = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }

  tags = data.azurerm_resource_group.app.tags
}

resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "app" {
  scope                = azurerm_storage_container.files.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_storage_management_policy" "history" {
  storage_account_id = azurerm_storage_account.app.id
  rule {
    name    = "expirePreviousVersions"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}
