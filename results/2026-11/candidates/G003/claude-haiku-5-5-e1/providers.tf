provider "azurerm" {
  # Credentials (ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_TENANT_ID, and either
  # ARM_CLIENT_SECRET or federated/OIDC settings) are read from the environment.
  features {}

  # Only register the resource providers this module needs, not every provider
  # in the subscription; avoids requiring subscription-wide registration rights.
  resource_provider_registrations = "none"
}
