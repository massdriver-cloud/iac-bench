terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81.0"
    }
  }
}

provider "azurerm" {
  features {
    storage {
      # Provision using ARM, including when the runner cannot reach a private endpoint.
      data_plane_available = false
    }
  }

  resource_provider_registrations = "none"
}
