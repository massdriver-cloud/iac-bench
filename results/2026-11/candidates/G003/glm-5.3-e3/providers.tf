provider "azurerm" {
  features {}

  # Credentials (ARM_*) come from the environment. The subscription can be
  # pinned per deployment when several subscriptions share one environment.
  subscription_id = var.subscription_id
}
