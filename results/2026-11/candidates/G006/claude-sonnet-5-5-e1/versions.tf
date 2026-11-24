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
  # Containers are managed through the ARM API (storage_account_id), so no
  # shared key or data-plane access is needed by the deployer.
  storage_use_azuread = true
}
