terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials and subscription come from the environment (ARM_* variables / az CLI).
provider "azurerm" {
  features {}
}
