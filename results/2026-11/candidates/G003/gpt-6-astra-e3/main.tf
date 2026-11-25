locals {
  tags = merge(var.tags, { managed_by = "opentofu" })
  platform_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.main.instrumentation_key
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
    WEBSITE_WARMUP_PATH                   = var.health_check_path
    WEBSITE_WARMUP_STATUSES               = "200"
    WEBSITE_HEALTHCHECK_MAXPINGFAILURES   = "3"
  }
  production_settings = merge(var.app_settings, local.platform_settings)
  staging_settings    = merge(var.app_settings, var.staging_app_settings, local.platform_settings)
}

resource "azurerm_resource_group" "main" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_linux_web_app" "main" {
  name                                           = var.name
  resource_group_name                            = azurerm_resource_group.main.name
  location                                       = azurerm_resource_group.main.location
  service_plan_id                                = local.service_plan_id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  app_settings                                   = local.production_settings
  tags                                           = local.tags

  identity { type = "SystemAssigned" }

  site_config {
    always_on                               = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.acr_resource_id != null
    vnet_route_all_enabled                  = var.vnet_route_all_enabled
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry_url
    }
  }

  sticky_settings {
    app_setting_names = distinct(concat(var.slot_sticky_settings, ["APPLICATIONINSIGHTS_CONNECTION_STRING", "APPINSIGHTS_INSTRUMENTATIONKEY"]))
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.vnet_route_all_enabled || var.integration_subnet_id != null
      error_message = "Route-all requires an integration subnet."
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.main.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  app_settings                                   = local.staging_settings
  tags                                           = local.tags

  identity { type = "SystemAssigned" }

  site_config {
    always_on                               = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.acr_resource_id != null
    vnet_route_all_enabled                  = var.vnet_route_all_enabled
    application_stack {
      docker_image_name   = coalesce(var.staging_image, var.container_image)
      docker_registry_url = var.registry_url
    }
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_role_assignment" "production_acr_pull" {
  count                = var.acr_resource_id == null ? 0 : 1
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_acr_pull" {
  count                = var.acr_resource_id != null && var.staging_enabled ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
