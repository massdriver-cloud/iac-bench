terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.20.0, < 5.0.0"
    }
  }
}

# Credentials and the target subscription come from the environment
# (ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ... or an Azure CLI login).
provider "azurerm" {
  features {
    application_insights {
      # Azure otherwise auto-creates an unmanaged "Failure Anomalies" rule and
      # action group next to Application Insights. They are invisible to this
      # module and block a clean destroy of the resource group; alerting is
      # declared explicitly in observability.tf instead.
      disable_generated_rule = true
    }
  }
}
