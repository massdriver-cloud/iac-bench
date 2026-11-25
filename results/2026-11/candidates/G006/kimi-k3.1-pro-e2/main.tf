data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  # Storage account names are global, lowercase, alphanumeric, and at most 24
  # characters. The subscription-scoped resource group ID makes this stable and
  # unique across applications, environments, and subscriptions.
  application_slug = join("", regexall("[a-z0-9]", lower(var.application_name)))
  account_name     = "st${substr(local.application_slug, 0, 10)}${substr(sha256(data.azurerm_resource_group.this.id), 0, 12)}"

  tags = merge(
    data.azurerm_resource_group.this.tags,
    {
      application = var.application_name
      managed_by  = "opentofu"
      component   = "application-storage"
    },
    var.tags,
  )
}

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  public_network_access_enabled     = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  is_hns_enabled                    = false
  nfsv3_enabled                     = false
  sftp_enabled                      = false
  local_user_enabled                = false

  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }

    restore_policy {
      days = 7
    }
  }

  # Applications authenticate with Entra ID. Leaving the HTTPS endpoint
  # reachable supports AKS and App Service without requiring network inputs.
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices", "Logging", "Metrics"]
  }

  tags = local.tags
}

# Container management uses the Azure control plane. This keeps container
# creation compatible with shared-key authentication being disabled.
resource "azapi_resource" "container" {
  for_each = var.containers

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.value
  parent_id = "${azurerm_storage_account.this.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_role_assignment" "application_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
}
