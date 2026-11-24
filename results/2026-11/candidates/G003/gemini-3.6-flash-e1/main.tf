terraform {
  required_version = ">= 1.6.0"
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

locals {
  rg_name  = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  location = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location

  default_tags = merge(
    {
      "Environment" = var.environment
      "Service"     = var.service_name
      "ManagedBy"   = "OpenTofu"
    },
    var.tags
  )

  app_insights_key        = var.enable_app_insights ? azurerm_application_insights.this[0].instrumentation_key : null
  app_insights_connection = var.enable_app_insights ? azurerm_application_insights.this[0].connection_string : null

  default_app_settings = merge(
    {
      "WEBSITES_PORT"                              = tostring(var.container_port)
      "DOCKER_ENABLE_CI"                           = "true"
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"        = "false"
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    },
    var.enable_app_insights ? {
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = local.app_insights_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = local.app_insights_connection
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    } : {},
    var.app_settings
  )
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = coalesce(var.resource_group_name, "rg-${var.service_name}-${var.environment}")
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.service_name}-${var.environment}"
  location               = local.location
  resource_group_name    = local.rg_name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = local.default_tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.service_name}-${var.environment}"
  resource_group_name = local.rg_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.default_tags

  profile {
    name = "AutoScalingProfile"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.cpu_scale_out_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.cpu_scale_in_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.memory_scale_out_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.memory_scale_in_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.enable_app_insights && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "log-${var.service_name}-${var.environment}"
  location            = local.location
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_in_days
  tags                = local.default_tags
}

resource "azurerm_application_insights" "this" {
  count               = var.enable_app_insights ? 1 : 0
  name                = "appi-${var.service_name}-${var.environment}"
  location            = local.location
  resource_group_name = local.rg_name
  workspace_id        = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id
  application_type    = "web"
  tags                = local.default_tags
}

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.service_name}-${var.environment}"
  location            = local.location
  resource_group_name = local.rg_name
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  tags                = local.default_tags

  app_settings = local.default_app_settings

  identity {
    type = "SystemAssigned"
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_minutes

    application_stack {
      docker_image_name        = var.docker_image_name
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true
  tags           = local.default_tags

  app_settings = local.default_app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_minutes

    application_stack {
      docker_image_name        = var.docker_image_name
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.enable_app_insights || var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "ds-${var.service_name}-${var.environment}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
