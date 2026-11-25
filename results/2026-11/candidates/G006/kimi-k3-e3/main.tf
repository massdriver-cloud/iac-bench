# ============================================================================
# app-storage — the standard way an application team gets Azure Storage.
#
# One call gives an application:
#   * one conventionally named, globally unique StorageV2 account living in
#     the application's own resource group;
#   * the private blob containers the application asked for;
#   * "Storage Blob Data Contributor" for the application's Entra ID
#     identity, so code on AKS / App Service uses its managed identity and
#     never touches an account key or connection string;
#   * platform-chosen defaults for everything else (HTTPS-only, TLS 1.2,
#     no anonymous access, soft delete, standard tags, ...).
# ============================================================================

data "azurerm_client_config" "current" {}

# Only read when `location` is left unset, so the account follows the
# resource group's region without the team having to think about it.
data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0

  name = var.resource_group_name
}

locals {
  # Storage account names are 3-24 chars, lowercase alphanumerics only, and
  # globally unique across all of Azure. "st" + app + environment keeps the
  # name human-readable; an 8-char hash of (subscription, resource group,
  # app, environment) keeps it unique and stable from plan to plan. The slug
  # is truncated, never the hash, so uniqueness survives long app names.
  name_slug = lower(replace("${var.app_name}${var.environment}", "/[^a-z0-9]/", ""))
  unique_suffix = substr(sha1(join("/", [
    data.azurerm_client_config.current.subscription_id,
    var.resource_group_name,
    var.app_name,
    var.environment,
  ])), 0, 8)
  generated_name       = "st${substr(local.name_slug, 0, 14)}${local.unique_suffix}"
  storage_account_name = var.storage_account_name != null ? var.storage_account_name : local.generated_name

  location = var.location != null ? var.location : data.azurerm_resource_group.this[0].location

  tags = merge(
    {
      application = var.app_name
      environment = var.environment
      managed-by  = "opentofu"
      module      = "app-storage"
    },
    var.tags,
  )
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = local.location

  # General-purpose v2 on Standard/Hot covers the app workloads this module
  # is for: user uploads, images and videos, generated reports and exports.
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = var.access_tier

  # Transport security: HTTPS only, modern TLS.
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Data security: no anonymous blob access, OAuth-first, no replication of
  # data to other Entra tenants.
  allow_nested_items_to_be_public  = false
  default_to_oauth_authentication  = true
  cross_tenant_replication_enabled = false

  # Applications authenticate with their Entra ID identity (see the role
  # assignment below). Shared keys stay enabled only so this module can
  # provision containers over the data plane; they are never output and
  # never handed to apps. See var.shared_access_key_enabled.
  shared_access_key_enabled = var.shared_access_key_enabled

  blob_properties {
    versioning_enabled = var.blob_versioning_enabled

    # Accidental deletes — of individual blobs and of whole containers —
    # stay recoverable for soft_delete_retention_days.
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  # Public endpoint over HTTPS by default: apps on AKS and App Service reach
  # it with zero network plumbing, and data-plane access is still gated by
  # Entra ID RBAC. var.network tightens this to a firewall without changing
  # the module.
  network_rules {
    default_action             = var.network.default_action
    bypass                     = ["AzureServices"]
    ip_rules                   = var.network.ip_rules
    virtual_network_subnet_ids = var.network.subnet_ids
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

# The application's own identity gets data-plane access. principal_type
# tells Azure not to resolve the principal in the directory first, which
# also makes this work for freshly created managed identities.
resource "azurerm_role_assignment" "app_data_plane" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.identity_principal_id
  principal_type       = "ServicePrincipal"
}

# Optional lifecycle management, e.g. expire re-generatable exports or cool
# down old uploads. Only created when the team asks for rules.
resource "azurerm_storage_management_policy" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = { for r in var.lifecycle_rules : r.name => r }

    content {
      name    = rule.value.name
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = length(rule.value.prefixes) > 0 ? rule.value.prefixes : null
      }

      actions {
        dynamic "base_blob" {
          for_each = (
            rule.value.tier_to_cool_after_days != null ||
            rule.value.tier_to_archive_after_days != null ||
            rule.value.delete_after_days != null
          ) ? [rule.value] : []

          content {
            tier_to_cool_after_days_since_modification_greater_than    = base_blob.value.tier_to_cool_after_days
            tier_to_archive_after_days_since_modification_greater_than = base_blob.value.tier_to_archive_after_days
            delete_after_days_since_modification_greater_than          = base_blob.value.delete_after_days
          }
        }

        dynamic "snapshot" {
          for_each = rule.value.snapshot_delete_after_days != null ? [rule.value] : []

          content {
            delete_after_days_since_creation_greater_than = snapshot.value.snapshot_delete_after_days
          }
        }
      }
    }
  }
}
