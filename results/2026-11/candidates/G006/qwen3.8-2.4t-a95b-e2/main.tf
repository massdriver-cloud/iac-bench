resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name
  location            = local.location

  # General purpose v2, standard tier, hot access: the right shape for active
  # application data (uploads, media, generated files).
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Security posture for application data:
  #  - TLS 1.2+ and HTTPS only,
  #  - no anonymous/public access to any container or blob,
  #  - Entra ID is the way in: shared access keys are disabled by default,
  #    and the portal defaults to OAuth when a key fallback would apply,
  #  - no SFTP/local users.
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = true
  public_network_access_enabled   = true
  local_user_enabled              = false

  # Double encryption at rest (infrastructure layer) at no meaningful cost.
  infrastructure_encryption_enabled = true

  # Application file storage uses blobs; no Data Lake / HDFS requirements.
  is_hns_enabled = false

  # Data protection: accidental blob or container deletion can be undone for
  # 7 days. Versioning/change feed stay off - apps manage their own data.
  blob_properties {
    versioning_enabled       = false
    change_feed_enabled      = false
    last_access_time_enabled = false

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# Containers the application needs for its data. All private - access is
# controlled per identity via Entra ID role assignments, never container ACLs.
resource "azurerm_storage_container" "this" {
  for_each = var.blob_containers

  name = each.value

  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
