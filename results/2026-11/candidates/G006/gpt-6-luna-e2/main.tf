terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100, < 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "account_suffix" {
  length  = 7
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  # Azure storage account names are limited to 24 lowercase alphanumeric
  # characters. Leave room for a generated suffix to make the name globally unique.
  app_name_slug = substr(replace(lower(var.application_name), "/[^a-z0-9]/", ""), 0, 17)
  account_name  = "${local.app_name_slug}${random_string.account_suffix.result}"
  common_tags = merge(var.tags, {
    application = var.application_name
    managed_by  = "opentofu"
  })
}

resource "azurerm_storage_account" "app" {
  name                     = local.account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  public_network_access_enabled     = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "application_blob_access" {
  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_identity_principal_id
  principal_type       = "ServicePrincipal"
}
