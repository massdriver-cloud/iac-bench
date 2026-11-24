data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.application}-${var.environment}")
  is_prod             = var.environment == "prod"

  env_short = {
    dev     = "dev"
    test    = "tst"
    staging = "stg"
    prod    = "prd"
  }[var.environment]

  # Storage account names: 3-24 chars, lowercase alphanumeric, globally unique.
  # "st" + app (<=12) + env (3) + 6-char hash of the resource group ID (<=23 chars).
  account_name = format(
    "st%s%s%s",
    substr(replace(var.application, "-", ""), 0, 12),
    local.env_short,
    substr(sha1(lower(data.azurerm_resource_group.this.id)), 0, 6),
  )

  restrict_network = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0

  # Prod survives a zone outage and a regional outage of the primary; others are cheaper.
  replication_type = local.is_prod ? "GZRS" : "LRS"

  # Longer recovery window in prod.
  retention_days = local.is_prod ? 30 : 7

  tags = merge(var.tags, {
    application = var.application
    environment = var.environment
    managed-by  = "opentofu"
  })
}

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  tags                = local.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Security baseline
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = local.retention_days
    }

    container_delete_retention_policy {
      days = local.retention_days
    }
  }

  network_rules {
    default_action             = local.restrict_network ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }
}

# Containers are created through the management plane (storage_account_id), so
# neither shared keys nor data-plane access are needed by the deployer.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Old blob versions are not kept forever.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-old-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = 90
      }
    }
  }
}

resource "azurerm_role_assignment" "app" {
  for_each = var.app_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "reader" {
  for_each = var.reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "blob-audit"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_management_lock" "no_delete" {
  count = local.is_prod ? 1 : 0

  name       = "protect-storage"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Production application data. Remove the lock deliberately before deleting."
}
