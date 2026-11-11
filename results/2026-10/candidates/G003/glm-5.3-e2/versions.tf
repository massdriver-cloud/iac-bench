terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials (ARM_* environment variables or Azure CLI login) come from the
# environment; this root module is applied directly.
provider "azurerm" {
  features {}
}
