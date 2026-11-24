terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}

  # The account has shared access keys disabled (Entra ID only), so the
  # provider must use Azure AD for any data-plane operations (e.g. creating
  # blob containers).
  storage_use_azuread = true
}
