terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
  }
}

# Credentials and the target subscription come from the environment
# (ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, OIDC / managed identity ...).
provider "azurerm" {
  # The accounts this module builds have access keys switched off, so the
  # provider itself must talk to storage with Entra ID as well.
  storage_use_azuread = true

  features {
    storage {
      # The accounts are firewalled by default. Everything in this module is
      # managed through the Azure Resource Manager API, so the pipeline never
      # needs a network path to the blob endpoint.
      data_plane_available = false
    }
  }
}
