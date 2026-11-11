terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.40.0, < 5.0.0"
    }
  }
}

# Subscription and credentials come from the environment (ARM_SUBSCRIPTION_ID, ARM_* / az login / OIDC).
provider "azurerm" {
  features {
    application_insights {
      # Azure silently drops a "Failure Anomalies" smart-detector rule and an action group next to
      # every Application Insights component. They are unmanaged and notify nobody useful; this
      # module ships explicit alerts instead.
      disable_generated_rule = true
    }

    resource_group {
      # Only affects the resource group this module creates itself ("rg-<name>"), which is dedicated
      # to the service. Azure-generated leftovers in it must not make `tofu destroy` fail half-way.
      # A resource group passed in via resource_group_name is never managed or deleted.
      prevent_deletion_if_contains_resources = false
    }
  }
}
