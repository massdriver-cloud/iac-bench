resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-law"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-ai"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.id
  sampling_percentage = var.application_insights_sampling_percentage
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                       = "${var.name}-to-law"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.deployment_slot_enabled ? 1 : 0

  name                       = "${var.name}-to-law"
  target_resource_id         = azurerm_linux_web_app_slot.this[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "this" {
  count = var.enable_metric_alerts ? 1 : 0

  name                = "${var.name}-alerts"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  enabled             = true
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = email_receiver.value.use_common_alert_schema
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.enable_metric_alerts ? 1 : 0

  name                = "${var.name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Production returned more than the configured number of HTTP 5xx responses in five minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.http_5xx_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = var.enable_metric_alerts ? 1 : 0

  name                = "${var.name}-slow-responses"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Production average response time exceeded the configured five-minute threshold."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true
  tags                = local.tags

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
}

resource "azurerm_monitor_metric_alert" "unhealthy_instances" {
  count = var.enable_metric_alerts && var.health_check_path != null ? 1 : 0

  name                = "${var.name}-unhealthy"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "At least one production instance is not healthy according to App Service health checks."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }
}
