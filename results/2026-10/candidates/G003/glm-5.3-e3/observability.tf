# ---------------------------------------------------------------------------
# Sinks: a Log Analytics workspace for platform/container logs and metrics, and
# workspace-based App Insights for application telemetry (connection string is
# injected into the container's environment automatically).
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}-${var.environment}"
  location            = local.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}-${var.environment}"
  location            = local.location
  resource_group_name = local.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Full-fidelity logs from both production and staging into Log Analytics,
# using dedicated (category-named) tables so queries stay simple.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                           = "send-to-log-analytics"
  target_resource_id             = azurerm_linux_web_app.this.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }
  enabled_log {
    category = "AppServiceAuditLogs"
  }
  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }
  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.create_staging_slot ? 1 : 0

  name                           = "send-to-log-analytics"
  target_resource_id             = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }
  enabled_log {
    category = "AppServiceAuditLogs"
  }
  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }
  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Alerting: an action group over the SRE inbox, plus the four signals that
# matter for a containerized HTTP API. Alerts exist even with no emails
# configured; they simply notify nobody until alert_emails is filled in.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "this" {
  count = length(var.alert_emails) > 0 ? 1 : 0

  name                = "ag-${var.name}-${var.environment}"
  resource_group_name = local.resource_group_name
  short_name          = substr(var.name, 0, 12)

  dynamic "email_receiver" {
    for_each = local.alert_email_receivers

    content {
      name          = email_receiver.key
      email_address = email_receiver.value
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "health_check" {
  name                = "${local.web_app_name}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "The App Service health check is failing on one or more instances; unhealthy instances are being evicted from the load balancer."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace       = "Microsoft.Web/sites"
    metric_name            = "HealthCheckStatus"
    aggregation            = "Average"
    operator               = "LessThan"
    threshold              = 1
    skip_metric_validation = true
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "${local.web_app_name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "More than 25 HTTP 5xx responses per 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 25
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "${local.web_app_name}-plan-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU sustained above 85% for 15 minutes; autoscale may not be keeping up with load."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "memory" {
  name                = "${local.web_app_name}-plan-memory"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan memory sustained above 90% for 15 minutes; the service is close to its memory ceiling."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]

    content {
      action_group_id = action.value
    }
  }
}
