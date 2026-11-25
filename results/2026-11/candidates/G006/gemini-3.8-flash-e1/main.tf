locals {
  # Resolve resource group name: defaults to "{application_name}-{environment}"
  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")

  # Clean strings for Azure storage naming (lowercase alphanumeric only, max 24 chars)
  clean_app = replace(lower(var.application_name), "/[^a-z0-9]/", "")
  clean_env = replace(lower(var.environment), "/[^a-z0-9]/", "")

  # Ensure prefix "st" (2 chars) + hash (6 chars) = 8 chars; budget 16 chars for app + env
  short_app = substr(local.clean_app, 0, 10)
  short_env = substr(local.clean_env, 0, 6)

  # Deterministic hash to guarantee global uniqueness per resource group and application
  name_hash = substr(sha256("${data.azurerm_resource_group.rg.id}-${var.application_name}-${var.environment}"), 0, 6)

  # Auto-generated standard storage account name
  default_storage_name = "st${local.short_app}${local.short_env}${local.name_hash}"
  storage_account_name = lower(coalesce(var.storage_account_name, local.default_storage_name))

  # Resolve location: fallback to the resource group's location
  location = coalesce(var.location, data.azurerm_resource_group.rg.location)

  # Smart replication type: ZRS for prod, LRS for non-prod environments
  replication_type = coalesce(
    var.account_replication_type,
    var.environment == "prod" ? "ZRS" : "LRS"
  )

  # Merge standard container names with custom container configurations
  all_containers = merge(
    { for c in var.containers : c => { container_access_type = "private", metadata = {} } },
    var.custom_containers
  )

  # Collect all application principal IDs for role assignments
  app_principal_ids = distinct(concat(
    var.application_principal_id != null ? [var.application_principal_id] : [],
    var.application_principal_ids
  ))

  # Standard tags enforced across all resources
  common_tags = merge({
    "application" = var.application_name
    "environment" = var.environment
    "managed-by"  = "opentofu"
  }, var.tags)
}

# Look up the application's existing Resource Group
data "azurerm_resource_group" "rg" {
  name = local.resource_group_name
}

# The Standard Azure Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = local.storage_account_name
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = local.location
  account_tier             = var.account_tier
  account_replication_type = local.replication_type
  account_kind             = "StorageV2"
  access_tier              = var.access_tier

  # Security & Compliance Baselines
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  allow_nested_items_to_be_public  = false
  default_to_oauth_authentication  = true
  cross_tenant_replication_enabled = false

  # Data protection & versioning
  blob_properties {
    versioning_enabled       = var.enable_blob_versioning
    last_access_time_enabled = true

    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }

  network_rules {
    default_action             = var.network_rules_default_action
    bypass                     = var.network_bypass
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = local.common_tags
}

# Application Blob Containers (uploads, images, reports, etc.)
resource "azurerm_storage_container" "containers" {
  for_each              = local.all_containers
  name                  = each.key
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = each.value.container_access_type
  metadata              = each.value.metadata
}

# Entra ID RBAC Role Assignment for Application Identity (AKS / App Service)
resource "azurerm_role_assignment" "app_roles" {
  for_each             = toset(local.app_principal_ids)
  scope                = azurerm_storage_account.storage.id
  role_definition_name = var.role_definition_name
  principal_id         = each.value
}

# Custom Role Assignments
resource "azurerm_role_assignment" "custom_roles" {
  for_each             = var.custom_role_assignments
  scope                = azurerm_storage_account.storage.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}

# Blob Lifecycle Management Policy (Optional)
resource "azurerm_storage_management_policy" "lifecycle" {
  count              = var.enable_lifecycle_management ? 1 : 0
  storage_account_id = azurerm_storage_account.storage.id

  rule {
    name    = "standard-blob-lifecycle"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = var.lifecycle_cool_after_days
        delete_after_days_since_modification_greater_than       = var.lifecycle_delete_after_days
      }
    }
  }
}
