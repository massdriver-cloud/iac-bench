locals {
  account_name      = var.name != null ? var.name : var.storage_account_name
  all_principal_ids = toset(concat(var.principal_ids, var.app_principal_ids))
}

resource "azurerm_storage_account" "this" {
  name                            = local.account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = var.account_tier
  account_replication_type        = var.account_replication_type
  account_kind                    = var.account_kind
  min_tls_version                 = var.min_tls_version
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = var.default_to_oauth_authentication
  public_network_access_enabled   = var.public_network_access_enabled

  blob_properties {
    versioning_enabled = var.enable_versioning

    dynamic "delete_retention_policy" {
      for_each = var.blob_soft_delete_retention_days > 0 ? [1] : []
      content {
        days = var.blob_soft_delete_retention_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_soft_delete_retention_days > 0 ? [1] : []
      content {
        days = var.container_soft_delete_retention_days
      }
    }
  }

  dynamic "network_rules" {
    for_each = (length(var.allowed_ips) > 0 || length(var.allowed_subnet_ids) > 0 || var.network_default_action == "Deny") ? [1] : []
    content {
      default_action             = var.network_default_action
      ip_rules                   = var.allowed_ips
      virtual_network_subnet_ids = var.allowed_subnet_ids
      bypass                     = var.network_bypass
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "containers" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_storage_queue" "queues" {
  for_each             = toset(var.queues)
  name                 = each.value
  storage_account_name = azurerm_storage_account.this.name
}

resource "azurerm_storage_table" "tables" {
  for_each             = toset(var.tables)
  name                 = each.value
  storage_account_name = azurerm_storage_account.this.name
}

resource "azurerm_storage_share" "shares" {
  for_each             = { for share in var.file_shares : share.name => share }
  name                 = each.value.name
  storage_account_name = azurerm_storage_account.this.name
  quota                = each.value.quota
}

resource "azurerm_role_assignment" "blob_contributor" {
  for_each             = local.all_principal_ids
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "custom" {
  for_each             = var.role_assignments
  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}
