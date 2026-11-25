provider "azurerm" {
  features {}

  # Use Entra ID (not account keys) for blob data-plane operations, matching
  # the account's shared_access_key_enabled = false setting.
  storage_use_azuread = true
}
