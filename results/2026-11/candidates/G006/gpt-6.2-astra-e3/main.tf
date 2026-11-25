terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

variable "resource_group_name" {
  description = "Name of the application's existing environment-specific resource group in the selected subscription."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && var.resource_group_name == trimspace(var.resource_group_name)
    error_message = "Enter a non-empty resource group name without surrounding whitespace."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the application's managed identity or service principal, not its client ID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.application_principal_id))
    error_message = "Enter the application's Entra principal object ID as a UUID."
  }
}

data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "app" {
  # One stable, Azure-compatible name per app environment.
  name                             = "app${substr(sha256(lower(data.azurerm_resource_group.app.id)), 0, 21)}"
  resource_group_name              = data.azurerm_resource_group.app.name
  location                         = data.azurerm_resource_group.app.location
  tags                             = data.azurerm_resource_group.app.tags
  account_kind                     = "StorageV2"
  account_tier                     = "Standard"
  account_replication_type         = "ZRS"
  access_tier                      = "Hot"
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  cross_tenant_replication_enabled = false

  blob_properties {
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "app_files" {
  scope                = azurerm_storage_container.files.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
}

output "storage_account_name" {
  description = "Name of the application's storage account."
  value       = azurerm_storage_account.app.name
}

output "blob_service_url" {
  description = "HTTPS service URL for a Blob SDK client using the application's Entra credential."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_name" {
  description = "Private blob container for application files."
  value       = azurerm_storage_container.files.name
}
