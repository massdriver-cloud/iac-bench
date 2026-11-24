# This module is designed to be planned and applied directly as a root module.
# Credentials are taken from the environment (`az login`, Azure CLI
# configuration, or ARM_* / AZURE_* environment variables) - nothing is
# hardcoded here.
provider "azurerm" {
  features {}

  # The module's default posture is Entra-only data access (storage account
  # keys are disabled), so any data-plane operations the provider performs on
  # this module's behalf (e.g. managing blob containers) use the caller's
  # Azure AD identity instead of account keys.
  storage_use_azuread = true
}
