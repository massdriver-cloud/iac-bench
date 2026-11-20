# Application resource groups the Azure briefs describe: G006's example
# application, orders, in staging and prod. Empty groups bill nothing.
# Applied once to the benchmark subscription; scoring substitutes
# orders-staging (AZURE_RESOURCE_GROUP) for a module's resource group input.

terraform {
  required_version = ">= 1.9"
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

variable "location" {
  description = "Region of the resource groups, and so of anything a module places in them by default."
  type        = string
  default     = "eastus2"
}

resource "azurerm_resource_group" "app" {
  for_each = toset(["orders-staging", "orders-prod"])
  name     = each.key
  location = var.location
}
