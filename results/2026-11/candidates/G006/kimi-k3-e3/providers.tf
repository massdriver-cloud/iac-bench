# This module is distributed and applied as a standalone root module, so it
# owns the provider configuration. Credentials and the target subscription
# come from the environment (ARM_* variables or Azure CLI).
provider "azurerm" {
  features {}
}
