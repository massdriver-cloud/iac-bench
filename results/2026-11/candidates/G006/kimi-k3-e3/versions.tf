terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Pinned to v3.x: the module uses the v3 argument names
      # (e.g. enable_https_traffic_only, storage_account_name on containers).
      version = "~> 3.100"
    }
  }
}
