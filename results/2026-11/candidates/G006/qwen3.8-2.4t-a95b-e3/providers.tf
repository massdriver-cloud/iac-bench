# Credentials (subscription, client id/secret or OIDC, tenant) come from the
# environment: ARM_SUBSCRIPTION_ID, ARM_TENANT_ID and the usual
# ARM_CLIENT_ID/ARM_CLIENT_SECRET or Azure CLI / workload identity variables.
provider "azurerm" {
  features {}
}
