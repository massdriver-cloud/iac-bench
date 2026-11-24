terraform {
  required_version = ">= 1.8.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}

provider "azurerm" {
  features {
    storage {
      # Provision and refresh using Azure Resource Manager, not the private blob endpoint.
      data_plane_available = false
    }
  }

  resource_provider_registrations = "none"
  storage_use_azuread             = true
}
