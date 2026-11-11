terraform {
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

resource "azurerm_resource_group" "probe" {
  name     = "rg-probe"
  location = "westeurope"
}

resource "azurerm_service_plan" "probe" {
  name                = "plan-probe"
  resource_group_name = azurerm_resource_group.probe.name
  location            = azurerm_resource_group.probe.location
  os_type             = "Linux"
  sku_name            = "P1v3"
}

# bad image name and bad registry url -> surface validators, if any
resource "azurerm_linux_web_app" "p1" {
  name                = "p1"
  resource_group_name = azurerm_resource_group.probe.name
  location            = azurerm_resource_group.probe.location
  service_plan_id     = azurerm_service_plan.probe.id

  site_config {
    always_on = true

    application_stack {
      docker_image_name   = "!!! bad name !!!"
      docker_registry_url = "not a url"
    }
  }
}

# registry url without scheme
resource "azurerm_linux_web_app" "p2" {
  name                = "p2"
  resource_group_name = azurerm_resource_group.probe.name
  location            = azurerm_resource_group.probe.location
  service_plan_id     = azurerm_service_plan.probe.id

  site_config {
    always_on = true

    application_stack {
      docker_image_name   = "nginx:latest"
      docker_registry_url = "index.docker.io"
    }
  }
}

# does container_registry_managed_identity_id still exist in site_config?
resource "azurerm_linux_web_app" "p3" {
  name                = "p3"
  resource_group_name = azurerm_resource_group.probe.name
  location            = azurerm_resource_group.probe.location
  service_plan_id     = azurerm_service_plan.probe.id

  site_config {
    always_on = true

    container_registry_use_managed_identity = true

    application_stack {
      docker_image_name = "myacr.azurecr.io/team/api:v1"
    }
  }
}

resource "azurerm_linux_web_app" "p4" {
  name                = "p4"
  resource_group_name = azurerm_resource_group.probe.name
  location            = azurerm_resource_group.probe.location
  service_plan_id     = azurerm_service_plan.probe.id

  site_config {
    always_on = true

    container_registry_managed_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/p/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai"
  }
}
