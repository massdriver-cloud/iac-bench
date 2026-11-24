data "azurerm_client_config" "current" {}

locals {
  application_slug = lower(replace(var.application_name, "/[^A-Za-z0-9]/", ""))

  # Storage account names are global. A recognizable application prefix makes
  # the account identifiable, while a deterministic subscription/RG hash avoids
  # collisions between teams, environments, and Azure subscriptions.
  generated_name = "st${substr(local.application_slug, 0, 8)}${substr(sha1("${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}/${var.application_name}"), 0, 12)}"
  account_name   = coalesce(var.storage_account_name, local.generated_name)

  standard_tags = {
    application = var.application_name
    component   = "application-storage"
    managed_by  = "OpenTofu"
  }

  network_is_restricted = length(var.allowed_ip_addresses) > 0 || length(var.allowed_subnet_ids) > 0
}

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  access_tier              = "Hot"

  # Application data is accessed with Entra ID. No account keys, anonymous
  # blobs, insecure transport, or legacy auxiliary protocols are needed.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  local_user_enabled              = false
  sftp_enabled                    = false
  nfsv3_enabled                   = false
  is_hns_enabled                  = false

  # Microsoft-managed encryption at rest, including infrastructure-level
  # encryption. Applications do not need to manage customer keys.
  infrastructure_encryption_enabled = true
  queue_encryption_key_type         = "Service"
  table_encryption_key_type         = "Service"
  allowed_copy_scope                = "AAD"
  cross_tenant_replication_enabled  = false

  # The endpoint remains usable from AKS/App Service without extra network
  # inputs. Authentication is still required. Supplying network rules opts in
  # to a deny-by-default perimeter.
  public_network_access_enabled = true

  network_rules {
    default_action             = local.network_is_restricted ? "Deny" : "Allow"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = tolist(var.allowed_ip_addresses)
    virtual_network_subnet_ids = tolist(var.allowed_subnet_ids)
  }

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    change_feed_retention_in_days = 30

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }

    # Seven days of point-in-time recovery, bounded by the 30-day soft-delete
    # and change-feed retention settings above.
    restore_policy {
      days = 7
    }
  }

  tags = merge(var.tags, local.standard_tags)
}

resource "azurerm_storage_container" "this" {
  for_each = var.container_names

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "application_blob_data" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_identity_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Application identity access to blobs in ${local.account_name}; container and blob read/write/delete, without account management or key access."
}
