# ---------------------------------------------------------------------------
# Standard application storage account.
#
# Design decisions owned by this module (so app teams don't have to):
#   * The account lives in the app's existing resource group and inherits its
#     region - storage should sit next to the compute that uses it.
#   * The globally-unique account name is generated from the resource group
#     name plus a stable random suffix; teams never have to invent one.
#   * Entra ID authentication only: shared access keys are disabled and every
#     app already has an Entra identity, which gets "Storage Blob Data
#     Contributor" on the account. No secrets to rotate or leak.
#   * Private by default: no anonymous blob access, HTTPS only, TLS 1.2+.
#   * Data protection on by default: blob/container soft delete and blob
#     versioning, with longer retention in prod.
#   * Environment-aware redundancy: ZRS in prod, LRS elsewhere.
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

# Stable random suffix so the account name is globally unique but does not
# churn on every plan. Only changes if the resource group changes.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false

  keepers = {
    resource_group = var.resource_group_name
  }
}

locals {
  is_prod = var.environment == "prod"

  # Storage account names: 3-24 chars, lowercase letters and digits only,
  # globally unique. "st" + up to 16 chars of the RG name + 6-char suffix.
  rg_compact   = replace(lower(var.resource_group_name), "/[^a-z0-9]/", "")
  account_name = "st${substr(local.rg_compact, 0, 16)}${random_string.suffix.result}"

  # Zone-redundant in prod (survives a datacentre failure), cheap LRS elsewhere.
  replication_type = local.is_prod ? "ZRS" : "LRS"

  # Longer recovery window for production data.
  soft_delete_days = local.is_prod ? 30 : 7

  tags = merge(
    {
      application = var.resource_group_name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )
}

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # --- Authentication: Entra ID only, no shared keys or anonymous access ---
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  public_network_access_enabled    = true
  allow_nested_items_to_be_public  = false
  local_user_enabled               = false
  cross_tenant_replication_enabled = false

  # --- Transport security ---
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # --- Data protection ---
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = local.soft_delete_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }
  }

  # Deny-by-default only when the team has explicitly listed allowed ranges;
  # otherwise authenticated traffic from anywhere (AKS egress IPs are dynamic).
  # Trusted Azure services (App Service, etc.) are always allowed through.
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      bypass         = ["AzureServices"]
      ip_rules       = var.allowed_ip_ranges
    }
  }

  tags = local.tags
}

# The application's own Entra identity gets read/write access to blob data.
# Scoped to this account only; no subscription-wide or key-based access.
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  skip_service_principal_aad_check = true
}

# Optional private containers for the app's files (uploads, reports, ...).
resource "azurerm_storage_container" "app" {
  for_each = var.blob_containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
