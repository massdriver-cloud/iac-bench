terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials are expected from the environment (ARM_CLIENT_ID,
# ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID, or an az CLI /
# managed-identity context for local development).
provider "azurerm" {
  features {}
}
