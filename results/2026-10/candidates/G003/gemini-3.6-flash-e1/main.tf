# Local variables to simplify logic
locals {
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location
  service_plan_id         = var.service_plan_id != null ? var.service_plan_id : azurerm_service_plan.this[0].id

  log_analytics_workspace_id = var.enable_application_insights ? (
    var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id
  ) : null

  app_insights_connection_string = var.enable_application_insights ? (
    var.application_insights_connection_string != null ? var.application_insights_connection_string : azurerm_application_insights.this[0].connection_string
  ) : null

  app_insights_instrumentation_key = var.enable_application_insights ? (
    var.application_insights_instrumentation_key != null ? var.application_insights_instrumentation_key : azurerm_application_insights.this[0].instrumentation_key
  ) : null
}

# Resource Group (created if create_resource_group is true)
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = coalesce(var.resource_group_name, "rg-${var.service_name}-${var.environment}")
  location = var.location
  tags     = var.tags
}

# App Service Plan (created if service_plan_id is not provided)
resource "azurerm_service_plan" "this" {
  count                  = var.service_plan_id == null ? 1 : 0
  name                   = "asp-${var.service_name}-${var.environment}"
  resource_group_name    = local.resource_group_name
  location               = local.resource_group_location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

# Autoscaling Setting for App Service Plan
resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.enable_autoscaling ? 1 : 0
  name                = "autoscale-${var.service_name}-${var.environment}"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  target_resource_id  = local.service_plan_id

  profile {
    name = "defaultProfile"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    # Scale out on High CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in on Low CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = var.tags
}

# Log Analytics Workspace for Application Insights and Diagnostic Settings
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.enable_application_insights && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "log-${var.service_name}-${var.environment}"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Application Insights
resource "azurerm_application_insights" "this" {
  count               = var.enable_application_insights && var.application_insights_connection_string == null ? 1 : 0
  name                = "appi-${var.service_name}-${var.environment}"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  tags                = var.tags
}

# Primary Linux Web App
resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.service_name}-${var.environment}"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  service_plan_id     = local.service_plan_id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                           = true
    ftps_state                          = "Disabled"
    minimum_tls_version                 = "1.2"
    http2_enabled                       = true
    health_check_path                   = var.health_check_path
    health_check_eviction_time_in_min   = var.health_check_eviction_time_in_minutes

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        action                    = ip_restriction.value.action
        priority                  = ip_restriction.value.priority
        description               = ip_restriction.value.description
      }
    }
  }

  app_settings = merge(
    {
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
      "PORT"                                 = tostring(var.container_port)
    },
    var.enable_application_insights && local.app_insights_connection_string != null ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = local.app_insights_connection_string
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = local.app_insights_instrumentation_key
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    } : {},
    var.app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  virtual_network_subnet_id = var.virtual_network_subnet_id

  tags = var.tags
}

# Diagnostic Settings for Primary Web App
resource "azurerm_monitor_diagnostic_setting" "app" {
  count                      = var.enable_diagnostic_settings && local.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${var.service_name}-${var.environment}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
