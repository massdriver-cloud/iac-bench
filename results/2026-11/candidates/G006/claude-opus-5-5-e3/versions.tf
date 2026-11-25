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

# Credentials and subscription come from the environment (ARM_* variables / az login).
provider "azurerm" {
  features {}

  # Shared keys are disabled on the account, so any data-plane call the provider
  # makes must authenticate with Entra ID.
  storage_use_azuread = true
}
