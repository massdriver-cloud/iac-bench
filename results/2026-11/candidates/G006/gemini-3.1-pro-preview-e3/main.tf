resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Storage account names can only consist of lowercase letters and numbers, and must be between 3 and 24 characters long.
  base_name = substr(replace(lower("${var.application_name}${var.environment}"), "/[^a-z0-9]/", ""), 0, 18)
  sa_name   = "${local.base_name}${random_string.suffix.result}"
}

resource "azurerm_storage_account" "this" {
  name                     = local.sa_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "ZRS" : "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  # Security best practices
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = {
    Application = var.application_name
    Environment = var.environment
  }
}

resource "azurerm_storage_container" "this" {
  for_each              = toset(var.containers)
  name                  = each.key
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "blob_data_contributor" {
  for_each             = toset(var.application_principal_ids)
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.key
}
