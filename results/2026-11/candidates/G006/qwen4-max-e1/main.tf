# ---------------------------------------------------------------------------
# Standard application storage account.
#
# Design decisions owned by this module (app teams should not have to think
# about these):
#   * Entra ID (identity) based data access only - storage account keys are
#     disabled. Apps on AKS / App Service use their existing managed identity,
#     granted "Storage Blob Data Contributor" below.
#   * HTTPS only, TLS 1.2 minimum, no anonymous/public blob access,
#     no cross-tenant replication, no SFTP/local users.
#   * Accidental-loss protection: blob versioning + soft delete for blobs
#     and containers.
#   * Zone-redundant (ZRS) in prod, locally-redundant (LRS) elsewhere.
#   * Globally-unique, predictable name derived from app + environment.
#   * Network access stays open at the firewall layer by default so AKS and
#     App Service outbound traffic works without extra networking setup;
#     the data plane is still protected by Entra ID authz on every request.
# ---------------------------------------------------------------------------

locals {
  is_prod = var.environment == "prod"

  replication_type           = coalesce(var.replication_type, local.is_prod ? "ZRS" : "LRS")
  soft_delete_retention_days = coalesce(var.soft_delete_retention_days, local.is_prod ? 14 : 7)

  # Storage account names: 3-24 chars, lowercase letters/digits only, globally
  # unique. Strip hyphens, cap the readable part at 19 chars and append a
  # stable 5-char random suffix so the name never collides across teams.
  name_base = substr(replace("${var.app_name}${var.environment}", "-", ""), 0, 19)

  storage_account_name = coalesce(
    var.storage_account_name_override,
    "${local.name_base}${random_string.name_suffix.result}",
  )

  tags = merge(
    {
      app         = var.app_name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )
}

resource "random_string" "name_suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Transport and encryption hardening.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  # Identity-first access: no account keys, no anonymous blob access,
  # no SFTP local users.
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  sftp_enabled                    = false
  local_user_enabled              = false

  # Public network endpoint stays reachable (AKS / App Service outbound),
  # but every data request must authenticate with Entra ID and pass RBAC.
  public_network_access_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = local.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_retention_days
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Private blob containers for the application's files.
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Data-plane access for the application's existing Entra ID identities
# (AKS workload identity / App Service managed identity).
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_blob_data_contributor" {
  for_each = var.application_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
