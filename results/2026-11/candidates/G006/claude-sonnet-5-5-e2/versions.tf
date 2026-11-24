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

  # Shared-key access is disabled on the accounts this module creates,
  # so any data-plane calls made by the provider must use Entra ID.
  storage_use_azuread = true
}
