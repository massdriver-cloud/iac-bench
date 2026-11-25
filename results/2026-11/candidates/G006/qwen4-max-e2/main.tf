# ---------------------------------------------------------------------------
# The application's resource group already exists (one per app per
# environment, e.g. "orders-staging"). We look it up — never create or
# manage it — and place the storage account in the same region so data
# stays next to the compute that uses it.
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

# ---------------------------------------------------------------------------
# Naming: storage account names must be globally unique, 3-24 chars,
# lowercase letters and digits only. Developers give us a friendly app
# name; we sanitize it and append a stable random suffix.
# ---------------------------------------------------------------------------

locals {
  # Strip anything Azure won't accept and cap the prefix so prefix+suffix <= 24.
  name_prefix = substr(lower(replace(var.name, "/[^a-z0-9]/", "")), 0, 18)

  storage_account_name = "${local.name_prefix}${random_string.suffix.result}"

  tags = merge(
    {
      "managed-by" = "opentofu"
      "workload"   = var.name
    },
    var.tags,
  )
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false

  # Regenerate the suffix only if the logical inputs change, so the
  # account name is stable across applies.
  keepers = {
    name           = local.name_prefix
    resource_group = var.resource_group_name
  }
}

# ---------------------------------------------------------------------------
# The storage account — the module's opinionated, secure standard:
#   * StorageV2 / Standard / Hot: general-purpose blob storage for app files.
#   * ZRS by default: survives a datacenter (availability-zone) failure.
#   * Entra ID only: shared access keys are disabled, so apps must use their
#     managed identity + RBAC (see role assignments below). No secrets to
#     rotate or leak.
#   * HTTPS-only, TLS 1.2 minimum, no anonymous/public blob access.
#   * Firewall defaults to Deny with trusted Azure services bypassed; teams
#     opt in their AKS/App Service subnets or debugging IPs explicitly.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  # Entra ID (managed identity + RBAC) is the only authentication path.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # Transport and exposure hardening.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

  # No SFTP/SSH local users, no NFS — this is blob storage for apps.
  sftp_enabled       = false
  nfsv3_enabled      = false
  local_user_enabled = false

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.virtual_network_subnet_ids
  }

  # Protect app files from accidental deletion/overwrite: deleted blobs
  # and containers are recoverable for 14 days, and overwrites/deletes
  # keep prior versions.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Private blob containers for the app's files. No anonymous access —
# everything goes through Entra ID + RBAC.
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Data-plane access for the application's existing Entra ID identities.
# 'Storage Blob Data Contributor' lets the app read/write/delete blobs and
# containers — exactly what an app storing its files needs — without any
# management-plane rights over the account itself.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "blob_contributor" {
  for_each = toset(var.principal_ids)

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
