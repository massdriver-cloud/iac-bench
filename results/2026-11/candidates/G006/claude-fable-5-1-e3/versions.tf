terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # Credentials and subscription come from the environment
  # (ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID or
  # a managed identity / Azure CLI login).
  features {}

  # Containers are managed via the Resource Manager API (storage_account_id),
  # so no data-plane key access is needed. Use Entra ID for anything that is.
  storage_use_azuread = true
}
