locals {
  # Resolve application name from inputs
  resolved_app_name = coalesce(var.application_name, var.app_name, "app")

  # Sanitize and truncate application name (alphanumeric only, lowercase, max 11 chars)
  clean_app     = lower(replace(local.resolved_app_name, "/[^a-zA-Z0-9]/", ""))
  truncated_app = substr(local.clean_app, 0, 11)

  # Normalize environment name to a clean 3-4 character standard code
  clean_env = lower(replace(var.environment, "/[^a-zA-Z0-9]/", ""))
  env_map = {
    production  = "prd"
    prod        = "prd"
    staging     = "stg"
    stage       = "stg"
    development = "dev"
    dev         = "dev"
    testing     = "tst"
    test        = "tst"
    qa          = "qa"
    uat         = "uat"
  }
  normalized_env = lookup(local.env_map, local.clean_env, substr(local.clean_env, 0, 4))

  # Deterministic 5-character suffix based on resource group, app, and environment
  unique_seed   = "${var.resource_group_name}-${local.resolved_app_name}-${var.environment}"
  unique_suffix = substr(md5(local.unique_seed), 0, 5)

  # Auto-generated name follows standard naming convention: st + app + env + suffix (length <= 22 chars)
  generated_name       = "st${local.truncated_app}${local.normalized_env}${local.unique_suffix}"
  storage_account_name = lower(coalesce(var.storage_account_name, local.generated_name))

  # Replication strategy: ZRS for production (zone resilience), LRS for non-prod (cost efficiency)
  is_prod          = contains(["prod", "production", "prd"], lower(var.environment))
  replication_type = var.replication_type != null ? var.replication_type : (local.is_prod ? "ZRS" : "LRS")

  # Identity aggregation for RBAC
  all_contributor_principals = distinct(compact(concat(
    var.principal_id != null ? [var.principal_id] : [],
    var.app_principal_id != null ? [var.app_principal_id] : [],
    var.principal_ids
  )))

  all_reader_principals = distinct(compact(var.reader_principal_ids))

  # Standard resource tags
  default_tags = {
    Application = local.resolved_app_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = var.account_tier
  account_replication_type = local.replication_type
  access_tier              = var.access_tier

  # Security & Compliance Defaults
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = var.allow_nested_items_to_be_public
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  public_network_access_enabled     = var.public_network_access_enabled

  # Blob Data Protection: soft delete, versioning, access time tracking
  blob_properties {
    versioning_enabled       = var.blob_versioning_enabled
    last_access_time_enabled = true

    delete_retention_policy {
      days = var.blob_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_delete_retention_days
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

  tags = local.merged_tags
}

resource "azurerm_storage_container" "this" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = var.container_access_type
}

# Role assignment granting application identity Storage Blob Data Contributor
resource "azurerm_role_assignment" "blob_contributor" {
  for_each                         = toset(local.all_contributor_principals)
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = var.role_definition_name
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}

# Role assignment granting reader identities Storage Blob Data Reader
resource "azurerm_role_assignment" "blob_reader" {
  for_each                         = toset(local.all_reader_principals)
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}
