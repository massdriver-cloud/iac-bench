# =============================================================================
# Observability: Log Analytics (created unless an existing workspace is given)
# =============================================================================

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "log-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_in_days
  tags                = local.tags
}

# =============================================================================
# Observability: Application Insights (workspace-based APM)
# =============================================================================

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  sampling_percentage = var.app_insights_sampling_percent
  tags                = local.tags
}

# =============================================================================
# Observability: platform logs and metrics for the app and the staging slot
# =============================================================================

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "logs-to-workspace"
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

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count = var.enable_staging_slot ? 1 : 0

  name                       = "logs-to-workspace"
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

# =============================================================================
# Observability: the on-call channel
# =============================================================================

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${var.name}"
  resource_group_name = local.resource_group_name
  short_name          = substr(var.name, 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_emails
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_url != null ? [1] : []
    content {
      name                    = "oncall-webhook"
      service_uri             = var.alert_webhook_url
      use_common_alert_schema = true
    }
  }
}

# =============================================================================
# Observability: standard alerts for an HTTP API
# =============================================================================

resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-${var.name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "More than ${var.alert_http_5xx_count} HTTP 5xx responses served in 5 minutes."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_http_5xx_count
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  name                = "alert-${var.name}-response-time"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average response time above ${var.alert_response_time_seconds}s for 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_seconds
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "alert-${var.name}-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Worker CPU above ${var.alert_cpu_percent}% for 15 minutes - autoscaling is not keeping up."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_cpu_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "memory" {
  name                = "alert-${var.name}-memory"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Worker memory above ${var.alert_memory_percent}% for 15 minutes."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_memory_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

# =============================================================================
# Health: synthetic availability test against the health endpoint
#
# Probes the app from multiple geographies every 5 minutes and expects a 200.
# Results land in Application Insights (availabilityResults) and the Log
# Analytics workspace. Automatically disabled when the app is not publicly
# reachable, since the probes originate from the public internet.
# =============================================================================

resource "azurerm_application_insights_standard_web_test" "this" {
  count = local.enable_availability_test ? 1 : 0

  name                    = "avail-${var.name}"
  resource_group_name     = local.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id
  geo_locations           = var.availability_test_locations
  frequency               = 300
  timeout                 = 60
  retry_enabled           = true
  tags                    = local.tags

  request {
    url = "https://${azurerm_linux_web_app.this.default_hostname}${local.availability_probe_path}"
  }

  validation_rules {
    expected_status_code = 200
  }
}
