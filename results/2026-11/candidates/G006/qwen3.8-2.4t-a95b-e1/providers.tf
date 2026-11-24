# Azure credentials are picked up from the environment (for example
# ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_SUBSCRIPTION_ID / ARM_TENANT_ID,
# or `az login`, or a managed identity), so no secrets live in this module.
provider "azurerm" {
  features {}
}
