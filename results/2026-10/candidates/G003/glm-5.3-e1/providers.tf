# This module is applied directly as a root module, so the provider is
# configured here. Credentials and subscription come from the environment
# (ARM_* variables / Azure CLI).
provider "azurerm" {
  features {}
}
