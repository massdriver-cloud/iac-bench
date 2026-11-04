terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  name_suffix = "${var.app_name}-${var.environment}"
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_suffix}"
  location = var.location
}

# Observability Resources
resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.id
}

# Capacity & Compute Resources
resource "azurerm_service_plan" "this" {
  name                   = "asp-${local.name_suffix}"
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_redundancy_enabled
}

# Main Application
resource "azurerm_linux_web_app" "this" {
  name                = "app-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id

  site_config {
    always_on                         = true
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 2

    application_stack {
      docker_image_name   = var.container_image_name
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = merge(
    {
      "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"   = "false"
    },
    var.app_settings
  )

  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# Staging Slot for Rollouts
resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  site_config {
    always_on                         = true
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 2

    application_stack {
      docker_image_name   = var.container_image_name
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = merge(
    {
      "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"   = "false"
    },
    var.app_settings
  )

  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# Diagnostic Settings to pipe metrics and logs to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "app_diag" {
  name                       = "diag-app-${local.name_suffix}"
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
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "slot_diag" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "diag-slot-${local.name_suffix}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
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
    enabled  = true
  }
}
