data "azurerm_resource_group" "app" {
  name = local.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.profile.replication_type
  access_tier              = "Hot"

  # Entra ID only: no account keys, no SAS tied to keys, no local users.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  # Transport and public exposure.
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false

  # Storage firewall: deny by default, allow the app's subnets and trusted Azure services.
  public_network_access_enabled = true
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  # Protect against accidental and malicious data loss.
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true
    delete_retention_policy {
      days = local.profile.soft_delete_days
    }
    container_delete_retention_policy {
      days = local.profile.soft_delete_days
    }
  }

  # Double encryption at rest (service and infrastructure layers).
  infrastructure_encryption_enabled = true

  # Not used by app workloads; keep off.
  sftp_enabled   = false
  nfsv3_enabled  = false
  is_hns_enabled = false

  tags = local.tags
}

# The application's own identity is the only data-plane principal.
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_storage_container" "this" {
  for_each = toset(local.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  # Reports and exports are written once and read rarely: tier to cool after 30 days.
  dynamic "rule" {
    for_each = local.cool_after_days_prefixes
    content {
      name    = "cool-${trimsuffix(rule.value, "/")}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = [rule.value]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than = 30
        }
      }
    }
  }
}

# Production storage holds user data; block accidental deletion of the account.
resource "azurerm_management_lock" "this" {
  count = local.profile.deletion_lock ? 1 : 0

  name       = "${azurerm_storage_account.this.name}-nodelete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Production application storage. Remove the lock before decommissioning."
}
