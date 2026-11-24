########################################
# Log Analytics + Application Insights
########################################

resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = "${var.name}-law"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-appi"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  tags                = local.tags
}

########################################
# Diagnostic settings (platform + request logs to the workspace)
########################################

locals {
  diagnostic_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
  ]
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name                       = "${var.name}-staging-diag"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

########################################
# Baseline alerts
########################################

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "HTTP 5xx responses from ${var.name} exceeded ${var.alert_http_5xx_threshold} in 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_http_5xx_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-response-time"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average response time of ${var.name} exceeded ${var.alert_response_time_threshold_seconds}s over 5 minutes."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_threshold_seconds
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "One or more instances of ${var.name} are failing the health check at ${var.health_check_path}."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
