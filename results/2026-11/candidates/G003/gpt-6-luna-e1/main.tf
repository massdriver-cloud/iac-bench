terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "app" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "app" {
  name                = "asp-${var.service_name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = var.service_plan_sku
  worker_count        = var.instance_count
  tags                = var.tags
}

resource "azurerm_log_analytics_workspace" "app" {
  name                = "law-${var.service_name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "app" {
  name                = "appi-${var.service_name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  workspace_id        = azurerm_log_analytics_workspace.app.id
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

locals {
  required_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.app.connection_string
  }

  registry_settings = var.container_registry_username == null ? {} : {
    DOCKER_REGISTRY_SERVER_USERNAME = var.container_registry_username
    DOCKER_REGISTRY_SERVER_PASSWORD = var.container_registry_password
  }

  app_settings = merge(var.app_settings, local.required_app_settings, local.registry_settings)
}

resource "azurerm_linux_web_app" "app" {
  name                                           = var.service_name
  location                                       = azurerm_resource_group.app.location
  resource_group_name                            = azurerm_resource_group.app.name
  service_plan_id                                = azurerm_service_plan.app.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.integration_subnet_id
  app_settings                                   = local.app_settings
  tags                                           = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 2
    app_command_line                  = var.container_startup_command

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  lifecycle {
    precondition {
      condition     = (var.container_registry_username == null) == (var.container_registry_password == null)
      error_message = "container_registry_username and container_registry_password must either both be set or both be null."
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.create_staging_slot ? 1 : 0

  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.app.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.integration_subnet_id
  app_settings                                   = local.app_settings
  tags                                           = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 2
    app_command_line                  = var.container_startup_command

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${var.service_name}"
  target_resource_id         = azurerm_linux_web_app.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.create_staging_slot ? 1 : 0

  name                       = "diag-${var.service_name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
