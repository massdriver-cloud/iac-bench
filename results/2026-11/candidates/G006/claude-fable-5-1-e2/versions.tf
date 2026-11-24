terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.14.0, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
  }
}

provider "azurerm" {
  # Credentials and subscription come from the environment (ARM_* variables /
  # workload identity / Azure CLI). Data-plane calls, if any, use Entra ID.
  storage_use_azuread = true

  features {}
}
