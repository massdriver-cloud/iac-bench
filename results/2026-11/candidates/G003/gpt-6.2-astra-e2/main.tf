terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
provider "azurerm" {
  features {}
}
resource "azurerm_resource_group" "service" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}
locals {
  rg     = azurerm_resource_group.service.name
  region = azurerm_resource_group.service.location
  settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.port)
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
  })
}
resource "azurerm_service_plan" "service" {
  name                   = "${var.name}-plan"
  resource_group_name    = local.rg
  location               = local.region
  os_type                = "Linux"
  sku_name               = var.capacity.sku
  worker_count           = var.capacity.min
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = var.tags
  lifecycle { ignore_changes = [worker_count] }
}
resource "azurerm_user_assigned_identity" "pull" {
  count               = var.acr_id == null ? 0 : 1
  name                = "${var.name}-pull"
  resource_group_name = local.rg
  location            = local.region
  tags                = var.tags
}
resource "azurerm_role_assignment" "pull" {
  count                            = var.acr_id == null ? 0 : 1
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.pull[0].principal_id
  skip_service_principal_aad_check = true
}
resource "azurerm_linux_web_app" "service" {
  name                                           = var.name
  location                                       = local.region
  resource_group_name                            = local.rg
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  app_settings                                   = local.settings
  identity {
    type         = var.acr_id == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = azurerm_user_assigned_identity.pull[*].id
  }
  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_id != null
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.pull[*].client_id)
    application_stack {
      docker_image_name   = var.image
      docker_registry_url = var.registry_url
    }
  }
  tags       = var.tags
  depends_on = [azurerm_role_assignment.pull]
}
resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_image == null ? 0 : 1
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  app_settings                                   = local.settings
  identity {
    type         = var.acr_id == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = azurerm_user_assigned_identity.pull[*].id
  }
  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_id != null
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.pull[*].client_id)
    application_stack {
      docker_image_name   = var.staging_image
      docker_registry_url = var.registry_url
    }
  }
  tags = var.tags
}
