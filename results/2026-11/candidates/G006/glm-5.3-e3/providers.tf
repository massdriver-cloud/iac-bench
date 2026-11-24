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

  # Storage account keys are disabled by default (see `allow_shared_key_access`),
  # so the provider talks to the storage data plane with Entra ID authentication
  # as well.
  storage_use_azuread = true
}
