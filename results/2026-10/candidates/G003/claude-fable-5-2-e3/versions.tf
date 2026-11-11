terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Credentials and the target subscription come from the environment
# (ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ... or an az login).
provider "azurerm" {
  features {
    application_insights {
      # The module ships its own alert rules; do not let Application Insights
      # create an unmanaged "Failure Anomalies" rule next to them.
      disable_generated_rule = true
    }

    resource_group {
      # The resource group is dedicated to this one service. Azure still drops
      # a few unmanaged helper resources into it (for example the Application
      # Insights smart detection action group), which would otherwise make
      # every `tofu destroy` of the service fail.
      prevent_deletion_if_contains_resources = false
    }
  }
}
