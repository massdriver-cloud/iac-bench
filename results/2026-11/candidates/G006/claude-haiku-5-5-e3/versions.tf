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
  features {}

  # Storage accounts are created with shared key access disabled, so the
  # provider must reach the data plane (containers) with Entra ID credentials.
  storage_use_azuread = true
}
