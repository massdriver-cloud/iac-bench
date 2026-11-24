terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.9.0, < 5.0.0"
    }
  }
}

# Subscription, tenant and credentials come from the environment (ARM_* variables,
# workload identity, or an az login session).
provider "azurerm" {
  features {
    storage {
      # The account is private-only and has access keys disabled, so the machine
      # running tofu usually cannot reach the blob endpoint. Everything in this
      # module is managed through the Azure Resource Manager API instead.
      data_plane_available = false
    }
  }

  # Never fall back to account keys (they are disabled on the account).
  storage_use_azuread = true
}
