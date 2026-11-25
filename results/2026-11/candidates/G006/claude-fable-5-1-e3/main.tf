############################################################################
# Standard application storage account.
#
# Design decisions (owned by the platform team, not by the caller):
#   * One StorageV2 account per application per environment, living in the
#     application's own resource group, in that resource group's region.
#   * Entra ID only: shared keys are disabled, SAS is impossible, anonymous
#     blob access is impossible, SFTP/local users are off. The application
#     identity gets an RBAC data role; nothing else is granted.
#   * Encryption in transit (HTTPS, TLS 1.2) and double encryption at rest.
#   * Accidental-deletion protection: blob and container soft delete,
#     longer in prod. Prod additionally keeps a geo-redundant copy.
#   * Hot tier, because these are files the application actively works
#     with; a lifecycle rule cools blobs nobody has touched in 90 days and
#     brings them back to hot automatically when they are read again.
############################################################################

locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")
  is_prod             = var.environment == "prod"

  # Storage account names are globally unique, 3-24 chars, lowercase
  # alphanumerics only. "<app><env>" (trimmed) + a 6 char random suffix.
  name_prefix          = substr("${var.application_name}${var.environment}", 0, 18)
  storage_account_name = "${local.name_prefix}${random_string.suffix.result}"

  # Production gets a geo-redundant copy; everything else is locally redundant.
  replication_type = local.is_prod ? "GRS" : "LRS"

  # How long deleted blobs / containers can be recovered.
  soft_delete_retention_days = local.is_prod ? 30 : 14

  # Network rules only lock down when the caller gives us something to allow.
  restrict_network = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0

  # Azure rejects /31 and /32 CIDR notation; plain addresses are fine.
  allowed_ip_rules = [
    for ip in var.allowed_ip_ranges :
    endswith(ip, "/32") ? trimsuffix(ip, "/32") : ip
  ]

  tags = merge(
    var.tags,
    {
      application = var.application_name
      environment = var.environment
      managed-by  = "opentofu"
    },
  )
}

data "azurerm_resource_group" "app" {
  name = local.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # --- Authentication & exposure ------------------------------------------
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = true
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  cross_tenant_replication_enabled = false
  sftp_enabled                     = false
  local_user_enabled               = false

  # --- Encryption at rest ---------------------------------------------------
  infrastructure_encryption_enabled = true

  blob_properties {
    last_access_time_enabled = true

    delete_retention_policy {
      days = local.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_retention_days
    }
  }

  network_rules {
    default_action             = local.restrict_network ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = local.allowed_ip_rules
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Cool down blobs the application hasn't touched in 90 days; they are
# re-tiered to hot automatically the next time they are accessed.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "cool-untouched-blobs"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_last_access_time_greater_than = 90
        auto_tier_to_hot_from_cool_enabled                          = true
      }
    }
  }
}

# The application's identity is the only principal granted data access.
resource "azurerm_role_assignment" "application" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = var.application_can_write ? "Storage Blob Data Contributor" : "Storage Blob Data Reader"
  principal_id         = var.application_principal_id

  # Freshly created managed identities can take a minute to replicate across
  # Entra ID; this stops the assignment failing on a "principal not found".
  skip_service_principal_aad_check = true
}
