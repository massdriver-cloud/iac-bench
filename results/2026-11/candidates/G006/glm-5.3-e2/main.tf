# The resource group already exists (each application owns one per
# environment); the module only looks it up to learn its region when
# `location` is not supplied directly.
data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0

  name = var.resource_group_name
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = local.location

  # General-purpose v2 with standard performance and a hot access tier is the
  # right shape for application files (uploads, media, reports, exports).
  # Premium and hierarchical-namespace accounts are special cases this module
  # deliberately does not create.
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Security posture: Entra ID only. Keys, connection strings, SAS tokens,
  # local users and anonymous access are all off; transport is TLS 1.2+ only;
  # and no blob can ever be made publicly readable.
  shared_access_key_enabled         = var.allow_shared_key_access
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = local.public_network_access_enabled

  # Data protection: deletions are recoverable for a week, and versioning is
  # on so an overwritten or corrupted blob can be restored by the app or an
  # operator without a support ticket.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = local.network_default_action
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = var.allowed_ip_cidrs
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = local.tags
}
