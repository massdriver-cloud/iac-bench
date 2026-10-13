terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "name" {
  type = string
}

variable "image" {
  type = string
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = "eastus"
}

resource "azurerm_service_plan" "this" {
  name                = "asp-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  site_config {
    application_stack {
      docker_image_name   = var.image
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }
}

output "hostname" {
  value = azurerm_linux_web_app.this.default_hostname
}
