terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Copy this example, change the four inputs, done.
module "orders_staging_storage" {
  source = "../.."

  application_name = "orders"
  environment      = "staging"
  location         = "westeurope"

  # The object (principal) ID of the identity the orders service runs as -
  # e.g. its AKS workload identity or App Service managed identity.
  app_identity_principal_ids = ["00000000-0000-0000-0000-000000000000"]
}

output "blob_endpoint" {
  value = module.orders_staging_storage.primary_blob_endpoint
}
