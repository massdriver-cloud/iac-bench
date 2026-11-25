provider "azurerm" {
  features {}

  # Shared access keys are disabled on the account (see below), so all
  # storage data-plane operations this module performs (creating blob
  # containers) must authenticate with Entra ID instead of account keys.
  storage_use_azuread = true
}

# Identity running OpenTofu (CI/CD pipeline or a developer). Used for the
# deployer role assignment below.
data "azurerm_client_config" "current" {}

# Read only when `location` is not set, so the storage account lands in the
# same region as the application's resource group.
data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0

  name = var.resource_group_name
}

locals {
  location = var.location != null ? var.location : data.azurerm_resource_group.this[0].location
}

resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = local.location

  # General-purpose v2 blob storage. Standard tier is the right default for
  # application data; replication is the one durability/cost trade-off left
  # to the team (defaults to LRS).
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type

  # --- Security baseline, owned by this module, not negotiable per account ---
  https_traffic_only_enabled      = true     # no plain HTTP, ever
  min_tls_version                 = "TLS1_2" # nothing older than TLS 1.2
  allow_nested_items_to_be_public = false    # containers can never be made public
  shared_access_key_enabled       = false    # apps use their Entra identity; no keys/SAS exist to leak
  default_to_oauth_authentication = true     # portal and tooling default to Entra auth
  public_network_access_enabled   = true     # AKS / App Service reach the HTTPS public endpoint with Entra auth

  # Deleted blobs and containers (user uploads, reports, ...) stay
  # recoverable for 7 days.
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# --- Access for the application ---------------------------------------------
# The whole point of the module: the application's own Entra identity gets
# data-plane access. No keys, no SAS, no connection strings to store or leak.
resource "azurerm_role_assignment" "application" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.identity_principal_id
  principal_type       = "ServicePrincipal"
}

# The identity running OpenTofu needs data-plane access as well, otherwise it
# cannot create the containers below on an account whose shared keys are
# disabled.
resource "azurerm_role_assignment" "deployer" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- Containers ---------------------------------------------------------------
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  # Data-plane operations must wait until the role assignments exist.
  depends_on = [
    azurerm_role_assignment.application,
    azurerm_role_assignment.deployer,
  ]
}
