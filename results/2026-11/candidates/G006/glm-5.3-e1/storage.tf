# =============================================================================
# The storage account
# =============================================================================

# One Standard general-purpose v2 (StorageV2) account per application:
# object storage for uploads, media, reports and exports. The settings below
# are the platform standard and are deliberately not knobs:
#
#   * Standard tier, ZRS redundancy (see var.replication_type) - resilient to
#     a zone outage without the cost/latency trade-offs of premium storage.
#   * HTTPS only, TLS 1.2 minimum.
#   * Entra ID is the authentication path: shared key access is disabled
#     (var.shared_access_key_enabled) and OAuth is the default auth method,
#     which is exactly how AKS workload identities and App Service managed
#     identities talk to storage.
#   * No public blob access, no cross-tenant replication, no local users.
#   * Infrastructure (double) encryption at rest.
#   * Blob and container soft delete for 7 days, blob versioning on - a
#     mistaken delete or overwrite is always recoverable without a support
#     ticket.
resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = local.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = true
  local_user_enabled              = false

  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false

  infrastructure_encryption_enabled = true
  public_network_access_enabled     = var.public_network_access_enabled

  tags = local.common_tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  dynamic "network_rules" {
    for_each = local.network_rules_needed ? [1] : []

    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  lifecycle {
    precondition {
      condition     = var.private_dns_zone_id == null || var.private_endpoint_subnet_id != null
      error_message = "private_dns_zone_id can only be used together with private_endpoint_subnet_id."
    }
    precondition {
      condition     = var.private_endpoint_subnet_id == null || !var.shared_access_key_enabled
      error_message = "Private endpoints pair with Entra ID authentication; leave shared_access_key_enabled at its default of false."
    }
  }
}

# =============================================================================
# Containers
# =============================================================================

# Always private: applications (and temporary URLs they mint) are the only
# readers. Public container access is not supported by this module - serve
# files through the application or a CDN instead.
resource "azurerm_storage_container" "this" {
  for_each = { for c in var.containers : c.name => c }

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# =============================================================================
# Lifecycle management (cost control without data-loss surprises)
# =============================================================================

# Default policy per container, all values relative to days since the blob was
# last modified, and scoped to that container only:
#
#   * blobs          -> Cool tier after 90 days (rarely-touched uploads and old
#                       reports cost ~half as much to keep)
#   * versions and
#     snapshots      -> deleted after 180 days (bounded cost for recoverable
#                       history)
#   * blobs          -> never deleted automatically; opting in requires an
#                       explicit delete_after_days
#
# Per-container overrides live in var.containers; passing
# lifecycle = { enabled = false } turns lifecycle management off for that
# container.
locals {
  lifecycle_rules = [
    for c in var.containers : {
      name = c.name

      # "lifecycle-uploads" style rule names: management policy rule names
      # allow alphanumerics only.
      rule_name = "lifecycle${replace(c.name, "-", "")}"

      # Rules are scoped with a path prefix, which always starts with the
      # container name - so a rule can never leak onto another container.
      prefix_match = (c.lifecycle != null && c.lifecycle.prefix != null) ? "${c.name}/${trim(c.lifecycle.prefix, "/")}" : "${c.name}/"

      enabled = try(c.lifecycle.enabled, true)

      # The module default tiers blobs to Cool after 90 days. When a team
      # explicitly asks for archive or delete without naming a Cool age there
      # is no point stopping at Cool on the way out - so the default is
      # dropped instead of tripping Azure's "tiers must be in order" rule.
      cool_after_days = try(c.lifecycle.cool_after_days, null) != null ? c.lifecycle.cool_after_days : (
        (try(c.lifecycle.archive_after_days, null) != null || try(c.lifecycle.delete_after_days, null) != null) ? null : 90
      )

      archive_after_days = try(c.lifecycle.archive_after_days, null)
      delete_after_days  = try(c.lifecycle.delete_after_days, null)

      delete_versions_after_days  = coalesce(try(c.lifecycle.delete_versions_after_days, null), 180)
      delete_snapshots_after_days = coalesce(try(c.lifecycle.delete_snapshots_after_days, null), 180)
    }
    if try(c.lifecycle.enabled, true)
  ]
}

resource "azurerm_storage_management_policy" "this" {
  # A policy resource is only meaningful when at least one container keeps
  # lifecycle management enabled.
  count = length(local.lifecycle_rules) > 0 ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = local.lifecycle_rules

    content {
      name    = rule.value.rule_name
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = [rule.value.prefix_match]
      }

      actions {
        dynamic "base_blob" {
          for_each = (
            rule.value.cool_after_days != null ||
            rule.value.archive_after_days != null ||
            rule.value.delete_after_days != null
          ) ? [1] : []

          content {
            tier_to_cool_after_days_since_modification_greater_than    = rule.value.cool_after_days
            tier_to_archive_after_days_since_modification_greater_than = rule.value.archive_after_days
            delete_after_days_since_modification_greater_than          = rule.value.delete_after_days
          }
        }

        dynamic "snapshot" {
          for_each = rule.value.delete_snapshots_after_days != null ? [1] : []

          content {
            delete_after_days_since_creation_greater_than = rule.value.delete_snapshots_after_days
          }
        }

        dynamic "version" {
          for_each = rule.value.delete_versions_after_days != null ? [1] : []

          content {
            delete_after_days_since_creation = rule.value.delete_versions_after_days
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for r in local.lifecycle_rules :
        (r.cool_after_days == null || r.archive_after_days == null || r.cool_after_days < r.archive_after_days) &&
        (r.cool_after_days == null || r.delete_after_days == null || r.cool_after_days < r.delete_after_days) &&
        (r.archive_after_days == null || r.delete_after_days == null || r.archive_after_days < r.delete_after_days)
      ])
      error_message = "Lifecycle days must be strictly ordered per container: cool_after_days < archive_after_days < delete_after_days."
    }
    precondition {
      condition = alltrue([
        for r in local.lifecycle_rules :
        (r.cool_after_days == null || r.cool_after_days > 0) &&
        (r.archive_after_days == null || r.archive_after_days > 0) &&
        (r.delete_after_days == null || r.delete_after_days > 0) &&
        (r.delete_versions_after_days == null || r.delete_versions_after_days > 0) &&
        (r.delete_snapshots_after_days == null || r.delete_snapshots_after_days > 0)
      ])
      error_message = "All lifecycle day values must be positive whole numbers of days."
    }
  }
}
