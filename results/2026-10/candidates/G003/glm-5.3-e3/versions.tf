terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  # When null the provider falls back to ARM_SUBSCRIPTION_ID, or the Azure CLI's
  # default subscription, whichever the environment provides.
  subscription_id = var.subscription_id
}
