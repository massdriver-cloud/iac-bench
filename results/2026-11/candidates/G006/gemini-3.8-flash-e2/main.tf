locals {
  # Clean strings for Azure Storage Account naming (lowercase alphanumeric only, max 24 chars)
  clean_app = substr(replace(lower(var.application_name), "/[^a-z0-9]/", ""), 0, 12)
  env_clean = replace(lower(var.environment), "/[^a-z0-9]/", "")
  env_abbrev = lookup(
    {
      "staging"     = "stg"
      "production"  = "prd"
      "development" = "dev"
    },
    local.env_clean,
    substr(local.env_clean, 0, 4)
  )

  # Deterministic 6-character hex hash to guarantee global uniqueness across subscriptions/regions
  name_hash = substr(md5("${var.resource_group_name}-${var.application_name}"), 0, 6)

  # Auto-generated name: 2 ("st") + max 12 (app) + max 4 (env) + 6 (hash) = max 24 chars
  storage_account_name = var.storage_account_name != null ? var.storage_account_name : "st${local.clean_app}${local.env_abbrev}${local.name_hash}"

  # Default replication: GRS for production, LRS for non-production
  is_prod = contains(["prod", "production"], lower(var.environment))
  replication_type = var.account_replication_type != null ? var.account_replication_type : (
    local.is_prod ? "GRS" : "LRS"
  )

  # All principal IDs to receive the primary data role
  all_principal_ids = distinct(compact(concat([var.principal_id], var.additional_principal_ids)))

  # Standard organizational tags
  default_tags = {
    Application = var.application_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
  tags = merge(local.default_tags, var.tags)

  # Lifecycle policy flags
  has_simple_lifecycle = (
    var.lifecycle_cool_after_days > 0 ||
    var.lifecycle_archive_after_days > 0 ||
    var.lifecycle_delete_after_days > 0
  )
  has_custom_lifecycle = length(var.custom_lifecycle_rules) > 0
  enable_lifecycle     = local.has_simple_lifecycle || local.has_custom_lifecycle
}

###############################################################################
# Storage Account
###############################################################################

resource "azurerm_storage_account" "storage" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_replication_type = local.replication_type
  account_kind             = var.account_kind
  access_tier              = var.access_tier

  # Security Defaults
  min_tls_version                 = var.min_tls_version
  https_traffic_only_enabled      = var.https_traffic_only_enabled
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = var.default_to_oauth_authentication

  # Blob Service Settings (Soft Delete, Versioning, CORS)
  blob_properties {
    versioning_enabled = var.versioning_enabled

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

    dynamic "cors_rule" {
      for_each = var.cors_rules
      content {
        allowed_headers    = cors_rule.value.allowed_headers
        allowed_methods    = cors_rule.value.allowed_methods
        allowed_origins    = cors_rule.value.allowed_origins
        exposed_headers    = cors_rule.value.exposed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
      }
    }
  }

  # Network Firewall Rules
  network_rules {
    default_action             = var.network_default_action
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
    bypass                     = var.network_bypass
  }

  tags = local.tags
}

###############################################################################
# Blob Containers
###############################################################################

resource "azurerm_storage_container" "containers" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = var.container_access_type
}

###############################################################################
# Role Assignments (Entra ID RBAC for AKS / App Service identities)
###############################################################################

resource "azurerm_role_assignment" "app" {
  for_each             = toset(local.all_principal_ids)
  scope                = azurerm_storage_account.storage.id
  role_definition_name = var.role_definition_name
  principal_id         = each.value
}

resource "azurerm_role_assignment" "custom" {
  for_each             = var.role_assignments
  scope                = azurerm_storage_account.storage.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}

###############################################################################
# Lifecycle Management Policy
###############################################################################

resource "azurerm_storage_management_policy" "management_policy" {
  count              = local.enable_lifecycle ? 1 : 0
  storage_account_id = azurerm_storage_account.storage.id

  dynamic "rule" {
    for_each = local.has_simple_lifecycle ? [1] : []
    content {
      name    = "default-tiering-and-cleanup"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = var.lifecycle_cool_after_days > 0 ? var.lifecycle_cool_after_days : null
          tier_to_archive_after_days_since_modification_greater_than = var.lifecycle_archive_after_days > 0 ? var.lifecycle_archive_after_days : null
          delete_after_days_since_modification_greater_than          = var.lifecycle_delete_after_days > 0 ? var.lifecycle_delete_after_days : null
        }
      }
    }
  }

  dynamic "rule" {
    for_each = var.custom_lifecycle_rules
    content {
      name    = rule.value.name
      enabled = try(rule.value.enabled, true)

      filters {
        prefix_match = try(rule.value.prefix_match, null)
        blob_types   = try(rule.value.blob_types, ["blockBlob"])
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = try(rule.value.cool_after_days, null)
          tier_to_archive_after_days_since_modification_greater_than = try(rule.value.archive_after_days, null)
          delete_after_days_since_modification_greater_than          = try(rule.value.delete_after_days, null)
        }
      }
    }
  }
}
