terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # Credentials and subscription come from the environment (ARM_* variables).
  # storage_use_azuread makes any data-plane call authenticate with Entra ID,
  # which is required because the module disables shared-key access.
  storage_use_azuread = true

  features {}
}
