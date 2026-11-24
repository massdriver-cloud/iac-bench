terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.9.0, < 5.0.0"
    }
  }
}

# Credentials and the target subscription come from the environment
# (ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ... or an `az login` session).
provider "azurerm" {
  # Account keys are switched off on every account this module creates, so any
  # data-plane call the provider makes must use Entra ID as well.
  storage_use_azuread = true

  features {
    storage {
      # The account's firewall denies everything that is not explicitly allowed,
      # which normally includes the machine running `tofu`. Everything in this
      # module is managed through Azure Resource Manager, so tell the provider
      # not to poke the (unreachable) data-plane endpoints.
      data_plane_available = false
    }
  }
}
