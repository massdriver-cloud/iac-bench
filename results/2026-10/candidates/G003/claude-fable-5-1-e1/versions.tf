terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials and subscription come from the environment
# (ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID,
# or Azure CLI / managed identity).
provider "azurerm" {
  features {
    resource_group {
      # Protect against accidental deletion of a shared RG that still
      # contains out-of-band resources.
      prevent_deletion_if_contains_resources = true
    }
    application_insights {
      disable_generated_rule = false
    }
  }
}
