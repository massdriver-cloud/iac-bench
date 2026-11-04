# ---------------------------------------------------------------------------
# Logs & traces
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = local.staging_slot ? 1 : 0

  name                       = "diag-${var.name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = { for idx, addr in var.alert_email_addresses : idx => addr }
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_url != null ? [var.alert_webhook_url] : []
    content {
      name                    = "webhook"
      service_uri             = webhook_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.alerts_enabled ? 1 : 0

  name                = "alert-${var.name}-health-check"
  resource_group_name = azurerm_resource_group.this.name
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

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.alerts_enabled ? 1 : 0

  name                = "alert-${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "${var.name} returned more than ${var.alert_http_5xx_threshold} HTTP 5xx responses in 5 minutes."
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

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = var.alerts_enabled ? 1 : 0

  name                = "alert-${var.name}-response-time"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average response time of ${var.name} exceeded ${var.alert_response_time_seconds}s over 5 minutes."
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
    threshold        = var.alert_response_time_seconds
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
