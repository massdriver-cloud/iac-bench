terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
  }
}

# Credentials and subscription come from the environment (ARM_* variables / az login).
provider "azurerm" {
  features {}
}
