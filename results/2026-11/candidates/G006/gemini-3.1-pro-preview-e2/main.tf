terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

# Generate a random suffix to ensure storage account name uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Ensure storage account name is valid: only lowercase letters and numbers, max 24 chars
  sanitized_name = lower(replace("${var.application_name}${var.environment}", "/[^a-zA-Z0-9]/", ""))

  # Base name can be up to 18 chars to leave room for 6 char suffix
  base_name = substr(local.sanitized_name, 0, 18)
  sa_name   = "${local.base_name}${random_string.suffix.result}"
}

resource "azurerm_storage_account" "main" {
  name                = local.sa_name
  resource_group_name = var.resource_group_name
  location            = var.location
  account_tier        = "Standard"

  # Choose replication based on environment (ZRS/GRS for prod, LRS for non-prod)
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"

  # Security best practices
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # Force Entra ID authentication

  blob_properties {
    # Soft delete helps protect from accidental deletion
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = {
    Application = var.application_name
    Environment = var.environment
  }
}

# Create requested containers
resource "azurerm_storage_container" "containers" {
  for_each              = var.containers
  name                  = each.value
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Grant the application's identity permission to read/write data in the storage account
resource "azurerm_role_assignment" "app_blob_data_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_principal_id
}
