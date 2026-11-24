terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

locals {
  # Azure storage account names are globally unique and limited to 24 lowercase
  # letters and digits. A stable hash makes names distinct across apps and
  # environments without asking developers to invent a globally unique name.
  app_prefix           = replace(lower(var.application_name), "/[^a-z0-9]/", "")
  storage_account_name = "${substr(local.app_prefix, 0, min(length(local.app_prefix), 14))}${substr(sha256("${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}/${var.application_name}"), 0, 10)}"

  tags = merge(var.tags, {
    application = var.application_name
    managed_by  = "opentofu"
  })
}

resource "azurerm_storage_account" "app" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# Keep old versions recoverable for a month without retaining them forever.
resource "azurerm_storage_management_policy" "app" {
  storage_account_id = azurerm_storage_account.app.id

  rule {
    name    = "expire-previous-blob-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# The workload identity is pre-existing (for example, an AKS workload identity
# or an App Service managed identity). Grant data-plane access without enabling
# shared keys or creating an identity the application cannot use.
resource "azurerm_role_assignment" "application_blob_data" {
  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
}
