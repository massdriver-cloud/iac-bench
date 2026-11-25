locals {
  resource_group_name = var.resource_group_name_override != null ? var.resource_group_name_override : "${var.application_name}-${var.environment}"

  normalized_name_seed = replace(lower("${var.application_name}${var.environment}"), "/[^a-z0-9]/", "")

  storage_account_name = var.storage_account_name_override != null ? var.storage_account_name_override : substr("st${local.normalized_name_seed}", 0, 24)

  location = var.location != null ? var.location : one(data.azurerm_resource_group.this[*].location)

  default_tags = {
    application = var.application_name
    environment = var.environment
    managed_by  = "opentofu"
  }
}

data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0

  name = local.resource_group_name
}

resource "azurerm_storage_account" "this" {
  name                            = local.storage_account_name
  resource_group_name             = local.resource_group_name
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = var.account_replication_type
  account_kind                    = "StorageV2"
  access_tier                     = var.access_tier
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = var.allow_blob_public_access
  public_network_access_enabled   = var.public_network_access_enabled
  shared_access_key_enabled       = var.shared_access_key_enabled

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(local.default_tags, var.tags)
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "blob_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_principal_id
}