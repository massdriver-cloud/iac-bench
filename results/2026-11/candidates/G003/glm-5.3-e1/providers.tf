terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials (ARM_SUBSCRIPTION_ID / ARM_CLIENT_ID / ... or MSI) come from the
# environment, per team convention; this root module is applied directly.
provider "azurerm" {
  features {}
}
