locals {
  # Parse application_name and environment from resource_group_name (e.g. "orders-staging", "orders-prod")
  # when not explicitly provided by the caller.
  rg_parts = split("-", lower(var.resource_group_name))
  inferred_environment = length(local.rg_parts) > 1 && contains(
    ["dev", "development", "test", "qa", "uat", "stage", "staging", "preprod", "prod", "production"],
    local.rg_parts[length(local.rg_parts) - 1]
  ) ? local.rg_parts[length(local.rg_parts) - 1] : "default"

  inferred_app_name = (
    local.inferred_environment != "default" && length(local.rg_parts) > 1
    ? join("-", slice(local.rg_parts, 0, length(local.rg_parts) - 1))
    : lower(var.resource_group_name)
  )

  application_name = coalesce(var.application_name, local.inferred_app_name)
  environment      = coalesce(var.environment, local.inferred_environment)

  is_production = contains(["prod", "production"], lower(local.environment))

  # Default to GRS in production for geo-redundancy and LRS in non-production for cost efficiency,
  # while allowing teams to override with ZRS/GZRS/etc.
  account_replication_type = coalesce(
    var.replication_type,
    local.is_production ? "GRS" : "LRS"
  )

  # Build a valid 3-24 char lowercase alphanumeric storage account name when not explicitly provided:
  # st + sanitized app/env prefix (up to 12 chars) + 10 char deterministic hash of resource_group_name + app_name.
  sanitized_prefix = substr(
    replace(lower("${local.application_name}${local.environment == "default" ? "" : local.environment}"), "/[^a-z0-9]/", ""),
    0,
    12
  )
  name_hash = substr(sha256("${lower(var.resource_group_name)}:${lower(local.application_name)}"), 0, 10)
  generated_storage_account_name = substr(
    "st${local.sanitized_prefix}${local.name_hash}",
    0,
    24
  )
  storage_account_name = coalesce(var.storage_account_name, local.generated_storage_account_name)

  # Normalize principal map for primary + additional app identities
  all_app_principals = merge({ "primary" = var.app_principal_id }, var.additional_app_principal_ids)

  # Point-in-time restore requires versioning, change feed, and soft delete, and its retention must be < blob soft delete days.
  enable_pitr       = var.enable_point_in_time_restore && var.enable_versioning && var.enable_change_feed && var.blob_soft_delete_retention_days > 1
  pitr_restore_days = local.enable_pitr ? var.blob_soft_delete_retention_days - 1 : null

  # Automatically switch network default action to Deny if VNet subnets or IP rules are supplied, unless overridden
  effective_network_default_action = (
    length(var.virtual_network_subnet_ids) > 0 || length(var.allowed_ip_rules) > 0
    ? "Deny"
    : var.network_default_action
  )

  standard_tags = merge(
    {
      "application" = local.application_name
      "environment" = local.environment
      "managed-by"  = "opentofu"
      "module"      = "standard-app-storage"
    },
    var.tags
  )
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.account_replication_type
  access_tier              = "Hot"

  # Security hardening defaults:
  # - Enforce Entra ID RBAC authentication; disable legacy shared storage account keys
  # - Disallow anonymous public blob/container access across the entire account
  # - Enforce TLS 1.2 and HTTPS-only traffic
  # - Enable Microsoft-managed infrastructure encryption at rest
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  public_network_access_enabled     = true
  local_user_enabled                = false
  sftp_enabled                      = false

  # Limit SAS expiration window to 7 days maximum even for User Delegation SAS
  sas_policy {
    expiration_period = "07.00:00:00"
    expiration_action = "Log"
  }

  blob_properties {
    versioning_enabled            = var.enable_versioning
    change_feed_enabled           = var.enable_change_feed
    change_feed_retention_in_days = var.enable_change_feed ? var.change_feed_retention_in_days : null
    last_access_time_enabled      = true

    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }

    dynamic "restore_policy" {
      for_each = local.enable_pitr ? [1] : []
      content {
        days = local.pitr_restore_days
      }
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins    = var.cors_allowed_origins
        allowed_methods    = var.cors_allowed_methods
        allowed_headers    = ["x-ms-*", "content-type", "content-length", "content-md5", "accept", "origin", "range"]
        exposed_headers    = ["x-ms-*", "content-length", "content-type", "content-range", "etag"]
        max_age_in_seconds = 3600
      }
    }
  }

  network_rules {
    default_action             = local.effective_network_default_action
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = var.virtual_network_subnet_ids
    ip_rules                   = var.allowed_ip_rules
  }

  tags = local.standard_tags
}

# Create standard private blob containers for the application
resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Lifecycle management policy for cost optimization & version cleanup
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  # Rule 1: Clean up old non-current versions and optionally tier blobs from Hot -> Cool -> Archive
  rule {
    name    = "standard-lifecycle-and-version-cleanup"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      dynamic "base_blob" {
        for_each = (var.lifecycle_cool_after_days != null || var.lifecycle_archive_after_days != null) ? [1] : []
        content {
          tier_to_cool_after_days_since_last_access_time_greater_than = var.lifecycle_cool_after_days
          tier_to_archive_after_days_since_modification_greater_than  = var.lifecycle_archive_after_days
        }
      }

      version {
        delete_after_days_since_creation = var.lifecycle_delete_previous_versions_after_days
      }

      snapshot {
        delete_after_days_since_creation_greater_than = var.lifecycle_delete_previous_versions_after_days
      }
    }
  }

  # Rule 2: If an 'exports' container is used and lifecycle_delete_exports_after_days is set,
  # automatically expire generated reports/exports after the retention window.
  dynamic "rule" {
    for_each = (contains(var.containers, "exports") && var.lifecycle_delete_exports_after_days != null) ? [1] : []
    content {
      name    = "expire-generated-exports"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["exports/"]
      }

      actions {
        base_blob {
          delete_after_days_since_modification_greater_than = var.lifecycle_delete_exports_after_days
        }
      }
    }
  }
}

# Grant primary and additional application Entra ID identities data-plane access (Storage Blob Data Contributor by default)
resource "azurerm_role_assignment" "app_blob_access" {
  for_each = local.all_app_principals

  scope                = azurerm_storage_account.this.id
  role_definition_name = var.app_role_definition_name
  principal_id         = each.value
}

# Grant Storage Blob Delegator role so the application can generate short-lived User Delegation SAS tokens
# using its Entra ID identity without needing shared storage account keys.
resource "azurerm_role_assignment" "app_user_delegation_sas" {
  for_each = var.enable_user_delegation_sas ? local.all_app_principals : {}

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = each.value
}

# Grant optional read-only Entra ID identities Storage Blob Data Reader access
resource "azurerm_role_assignment" "readonly_blob_access" {
  for_each = var.readonly_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
