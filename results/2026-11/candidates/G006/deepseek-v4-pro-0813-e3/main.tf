data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0
  name  = var.resource_group_name
}

locals {
  location = var.location != null ? var.location : data.azurerm_resource_group.this[0].location

  # Sensible default: geo-redundant in prod, locally redundant everywhere else.
  replication_type = var.account_replication_type != null ? var.account_replication_type : (
    var.environment == "prod" ? "GRS" : "LRS"
  )

  name_app  = lower(replace(var.app_name, "/[^a-zA-Z0-9]/", ""))
  name_env  = lower(replace(var.environment, "/[^a-zA-Z0-9]/", ""))
  name_base = "${local.name_app}${local.name_env}st"

  storage_account_name = var.storage_account_name != null ? var.storage_account_name : "${substr(local.name_base, 0, 18)}${random_id.suffix[0].hex}"

  tags = merge(
    {
      Application = var.app_name
      Environment = var.environment
      ManagedBy   = "opentofu"
    },
    var.tags
  )
}

resource "random_id" "suffix" {
  count       = var.storage_account_name == null ? 1 : 0
  byte_length = 3
}

resource "azurerm_storage_account" "this" {
  name                            = local.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = local.location
  account_tier                    = var.account_tier
  account_replication_type        = local.replication_type
  account_kind                    = var.account_kind
  min_tls_version                 = var.min_tls_version
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  shared_access_key_enabled       = var.shared_access_key_enabled
  public_network_access_enabled   = var.public_network_access_enabled

  blob_properties {
    change_feed_enabled      = true
    versioning_enabled       = true
    last_access_time_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "blob_data_contributor" {
  count                = var.principal_id != null ? 1 : 0
  scope                = azurerm_storage_account.this.id
  role_definition_name = var.role_definition_name
  principal_id         = var.principal_id
}
