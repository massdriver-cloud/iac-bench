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
  features {
    storage {
      # This root manages storage through ARM, including private-only accounts.
      data_plane_available = false
    }
  }

  resource_provider_registrations = "none"
  storage_use_azuread             = true
}
