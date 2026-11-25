terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "registry.opentofu.org/hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # This module owns the whole resource group; tearing the module down
      # should not be blocked by resources Azure created implicitly inside it.
      prevent_deletion_if_contains_resources = false
    }
  }
}
