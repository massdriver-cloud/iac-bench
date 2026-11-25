terraform {
  required_version = ">= 1.6"
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
resource "azurerm_resource_group" "service" {
  name     = "rg-${var.service_name}"
  location = var.location
  tags     = var.tags
}
resource "azurerm_service_plan" "service" {
  name                   = "asp-${var.service_name}"
  resource_group_name    = azurerm_resource_group.service.name
  location               = azurerm_resource_group.service.location
  os_type                = "Linux"
  sku_name               = var.capacity.sku
  worker_count           = var.capacity.minimum
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = var.tags
  # After creation Azure Monitor owns target capacity, including fixed ranges.
  lifecycle { ignore_changes = [worker_count] }
}
locals {
  settings = merge(var.app_settings, {
    WEBSITES_PORT                       = tostring(var.container.port)
    WEBSITE_SWAP_WARMUP_PING_PATH       = var.health_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES   = "200"
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
  })
}
resource "azurerm_linux_web_app" "service" {
  name                                           = var.service_name
  resource_group_name                            = azurerm_resource_group.service.name
  location                                       = azurerm_resource_group.service.location
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  identity {
    type         = local.identity_type
    identity_ids = local.registry_identity_ids
  }
  app_settings = local.settings
  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    http2_enabled                                 = true
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.registry_identity != null
    container_registry_managed_identity_client_id = try(var.registry_identity.client_id, null)
    application_stack {
      docker_registry_url = var.container.registry_url
      docker_image_name   = var.container.image
    }
  }
  tags = var.tags
}
resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.candidate_image == null ? 0 : 1
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  identity {
    type         = local.identity_type
    identity_ids = local.registry_identity_ids
  }
  app_settings = local.settings
  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    http2_enabled                                 = true
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.registry_identity != null
    container_registry_managed_identity_client_id = try(var.registry_identity.client_id, null)
    application_stack {
      docker_registry_url = var.container.registry_url
      docker_image_name   = var.candidate_image
    }
  }
  tags = var.tags
}
