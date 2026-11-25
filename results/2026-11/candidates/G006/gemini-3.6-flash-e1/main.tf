terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  # Sanitize application_name and environment to lowercase alphanumeric only
  name_raw    = lower(replace("${var.application_name}${var.environment}", "/[^a-z0-9]/", ""))
  name_prefix = substr(local.name_raw, 0, 18)
  # Generate a deterministic 6-character hex hash based on RG and app name to guarantee global uniqueness
  name_hash       = substr(sha256("${var.resource_group_name}-${var.application_name}"), 0, 6)
  default_sc_name = "${local.name_prefix}${local.name_hash}"

  # Fallback: if user specified storage_account_name, use it; otherwise use generated default
  account_name = var.storage_account_name != null ? var.storage_account_name : local.default_sc_name

  default_tags = {
    Application = var.application_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }

  tags = merge(local.default_tags, var.tags)

  # Combine single principal ID and list of principal IDs into a single distinct list
  all_app_principal_ids = distinct(compact(concat(
    var.app_principal_ids,
    var.app_principal_id != null ? [var.app_principal_id] : []
  )))

  # Create pairs of principal ID and role name for RBAC role assignments
  principal_role_pairs = flatten([
    for principal in local.all_app_principal_ids : [
      for role in var.role_names : {
        principal = principal
        role      = role
      }
    ]
  ])
}

resource "azurerm_storage_account" "this" {
  name                             = local.account_name
  resource_group_name              = var.resource_group_name
  location                         = var.location
  account_tier                     = var.account_tier
  account_replication_type         = var.replication_type
  account_kind                     = var.account_kind
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = var.allow_nested_items_to_be_public
  shared_access_key_enabled        = var.shared_access_key_enabled
  public_network_access_enabled    = var.public_network_access_enabled
  default_to_oauth_authentication  = var.default_to_oauth_authentication
  cross_tenant_replication_enabled = var.cross_tenant_replication_enabled

  dynamic "blob_properties" {
    for_each = var.enable_blob_properties ? [1] : []
    content {
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
  }

  dynamic "network_rules" {
    for_each = var.network_rules != null ? [var.network_rules] : []
    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      ip_rules                   = network_rules.value.ip_rules
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each              = toset(var.containers)
  name                  = each.key
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_storage_share" "this" {
  for_each             = var.file_shares
  name                 = each.key
  storage_account_name = azurerm_storage_account.this.name
  quota                = each.value
}

resource "azurerm_storage_queue" "this" {
  for_each             = toset(var.queues)
  name                 = each.key
  storage_account_name = azurerm_storage_account.this.name
}

resource "azurerm_storage_table" "this" {
  for_each             = toset(var.tables)
  name                 = each.key
  storage_account_name = azurerm_storage_account.this.name
}

resource "azurerm_role_assignment" "app_roles" {
  for_each = {
    for pair in local.principal_role_pairs : "${pair.principal}-${pair.role}" => pair
  }
  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
}
