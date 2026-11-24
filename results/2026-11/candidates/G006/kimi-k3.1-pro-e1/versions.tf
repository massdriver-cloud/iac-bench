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

  # Containers are provisioned with the identity running OpenTofu, not with a
  # storage account key. Application access is also Entra ID-only.
  storage_use_azuread = true
}
