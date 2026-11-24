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

  # Data-plane storage operations (containers, shares, blobs) authenticate
  # with the provider's Entra ID credentials instead of storage account keys.
  # This module disables key-based authorization on the accounts it creates,
  # so the provider must not rely on keys either.
  storage_use_azuread = true
}
