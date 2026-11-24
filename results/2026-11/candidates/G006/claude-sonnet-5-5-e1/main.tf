data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

locals {
  is_prod             = var.environment == "prod"
  resource_group_name = coalesce(var.resource_group_name, "${var.application}-${var.environment}")

  # Storage account names: 3-24 chars, lowercase alphanumeric, globally unique.
  # "st" + app + env + 4-char hash of the resource group id for uniqueness.
  name_hash = substr(sha1(lower(data.azurerm_resource_group.this.id)), 0, 4)
  name_stem = replace("${var.application}${var.environment}", "-", "")
  name      = "st${substr(local.name_stem, 0, 24 - 2 - 4)}${local.name_hash}"

  replication_type = coalesce(var.replication_type, local.is_prod ? "GZRS" : "LRS")
  retention_days   = coalesce(var.blob_retention_days, local.is_prod ? 30 : 7)

  restrict_network = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0

  tags = merge(
    {
      application = var.application
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )

  writers = toset(var.app_principal_ids)
  readers = toset([for id in var.reader_principal_ids : id if !contains(var.app_principal_ids, id)])
}

resource "azurerm_storage_account" "this" {
  name                = local.name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

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
  local_user_enabled                = false
  sftp_enabled                      = false

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

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Old blob versions are removed after the retention window so versioning
# doesn't grow cost without bound.
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
        delete_after_days_since_creation = local.retention_days
      }
    }
  }
}

resource "azurerm_role_assignment" "writer" {
  for_each = local.writers

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "reader" {
  for_each = local.readers

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
