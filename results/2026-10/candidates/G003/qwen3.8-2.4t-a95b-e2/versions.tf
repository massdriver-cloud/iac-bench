terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials come from the environment (ARM_CLIENT_ID/ARM_CLIENT_SECRET/
# ARM_TENANT_ID/ARM_SUBSCRIPTION_ID or az CLI / managed identity).
provider "azurerm" {
  features {}
}
