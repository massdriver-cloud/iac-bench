locals {
  default_app_settings = {
    # Codeless agent + SDK connection string; teams instrument with the
    # OpenTelemetry/App Insights SDK of their choice using these.
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.this.instrumentation_key
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"

    # Containers don't need the shared home mount; disabling it removes a
    # class of "works until restart" storage quirks.
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = tostring(var.container_port)
  }

  app_service_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceAppLogs",
    "AppServiceConsoleLogs",
    "AppServiceAuditEvents",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs",
  ]
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-appi"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  application_type = "web"
  workspace_id     = azurerm_log_analytics_workspace.this.id

  tags = local.tags
}

# Platform + application logs and metrics flow to the workspace with
# resource-specific tables (Dedicated), which is what App Service supports.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                           = "${var.name}-diag"
  target_resource_id             = azurerm_linux_web_app.this.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.app_service_log_categories

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = local.slot_enabled ? 1 : 0

  name                           = "${var.name}-diag"
  target_resource_id             = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.app_service_log_categories

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# CPU is the most reliable generic saturation signal across the assorted
# HTTP APIs this module hosts; teams with queue- or request-driven workloads
# can layer extra rules on the same plan outside the module.
resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "cpu"

    capacity {
      minimum = tostring(var.autoscale_min_instances)
      maximum = tostring(var.autoscale_max_instances)
      default = tostring(var.instance_count)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        metric_namespace   = "Microsoft.Web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_scale_out_cpu_threshold
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
        metric_namespace   = "Microsoft.Web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_scale_in_cpu_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT15M"
      }
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_action_group" "this" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-alerts"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = substr(var.name, 0, 12)

  dynamic "email_receiver" {
    for_each = toset(var.alert_email_addresses)

    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "http5xx" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${local.web_app_name}-http5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "More than ${var.http5xx_alert_threshold} HTTP 5xx responses within 5 minutes on ${local.web_app_name}."

  severity    = 2
  frequency   = "PT1M"
  window_size = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.http5xx_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${local.web_app_name}-slow-responses"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average response time above ${var.response_time_alert_threshold_seconds}s for 5 minutes on ${local.web_app_name}."

  severity    = 3
  frequency   = "PT1M"
  window_size = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.response_time_alert_threshold_seconds
  }

  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }

  tags = local.tags
}
