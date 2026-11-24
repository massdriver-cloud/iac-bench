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

# Credentials are taken from the environment (ARM_* environment variables or
# an authenticated Azure CLI), as with every other module in this repo.
# `subscription_id` is only set by teams that cannot rely on
# ARM_SUBSCRIPTION_ID (e.g. pipelines that hop subscriptions); when left at its
# default of null the provider falls back to the environment.
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
