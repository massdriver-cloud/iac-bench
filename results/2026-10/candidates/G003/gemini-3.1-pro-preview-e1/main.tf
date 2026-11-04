terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.app_name}-law"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "this" {
  name                = "${var.app_name}-appinsights"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.app_name}-plan"
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled
}

resource "azurerm_linux_web_app" "this" {
  name                = var.app_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 5
  }

  app_settings = merge(
    {
      "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"   = "false"
    },
    var.app_settings
  )
}

resource "azurerm_monitor_diagnostic_setting" "app_diag" {
  name                       = "${var.app_name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 5
  }

  app_settings = merge(
    {
      "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"   = "false"
    },
    var.app_settings
  )
}
