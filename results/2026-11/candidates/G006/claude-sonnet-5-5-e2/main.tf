locals {
  is_prod             = var.environment == "prod"
  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")
  replication_type    = coalesce(var.replication_type, local.is_prod ? "GRS" : "LRS")

  # Storage account names: 3-24 chars, lowercase alphanumeric, globally unique.
  # "st" + app (max 11) + env (max 7) + 4 char hash of the resource group ID.
  name_app     = substr(replace(var.application_name, "-", ""), 0, 11)
  name_hash    = substr(sha1(data.azurerm_resource_group.app.id), 0, 4)
  name_prefix  = "st${local.name_app}${var.environment}"
  account_name = "${local.name_prefix}${local.name_hash}"

  restrict_network = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0

  recovery_days = local.is_prod ? 30 : 7

  tags = merge(var.tags, {
    application = var.application_name
    environment = var.environment
    managed-by  = "opentofu"
  })
}

data "azurerm_resource_group" "app" {
  name = local.resource_group_name
}

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Transport and authentication hardening
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  sftp_enabled                      = false
  cross_tenant_replication_enabled  = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = local.recovery_days
    }

    container_delete_retention_policy {
      days = local.recovery_days
    }
  }

  network_rules {
    default_action             = local.restrict_network ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Old blob versions and snapshots would otherwise accumulate forever.
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
      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }
}

resource "azurerm_role_assignment" "app" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "readers" {
  for_each = var.reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}
