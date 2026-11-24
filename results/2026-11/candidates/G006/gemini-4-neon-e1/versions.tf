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
  # Use Entra ID (OAuth) for any Azure Storage data-plane operations because
  # this module disables Shared Key authentication by default.
  storage_use_azuread = true

  features {}
}
