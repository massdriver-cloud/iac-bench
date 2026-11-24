# =====================================================================================================================
# Observability: Log Analytics & Application Insights
# =====================================================================================================================

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.log_analytics_workspace_id == null ? 1 : 0
  name                = local.law_name
  resource_group_name = local.resource_group_name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  count               = var.application_insights_connection_string == null ? 1 : 0
  name                = local.ai_name
  resource_group_name = local.resource_group_name
  location            = local.location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  tags                = local.tags
}

# =====================================================================================================================
# Diagnostic Settings: Production App Service
# =====================================================================================================================

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${local.app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

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
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# =====================================================================================================================
# Diagnostic Settings: Staging Deployment Slot
# =====================================================================================================================

resource "azurerm_monitor_diagnostic_setting" "slot" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "diag-${local.app_name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

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
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# =====================================================================================================================
# SRE Metric Alerts: Operational Health & Availability
# =====================================================================================================================

# 1. High HTTP 5xx Server Errors (SLO / Availability Impact)
resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggered when HTTP 5xx errors exceed acceptable SLO threshold"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_5xx_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 2. High CPU Utilization (Capacity / Performance Degradation)
resource "azurerm_monitor_metric_alert" "cpu_high" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-cpu-high"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggered when container CPU usage is dangerously high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_cpu_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 3. High Latency / Average Response Time (User Experience / SLO)
resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-response-time"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggered when average HTTP API response time exceeds latency SLO"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 4. High Memory Utilization (Resource Exhaustion)
resource "azurerm_monitor_metric_alert" "memory_high" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-memory-high"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggered when container memory usage is dangerously high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_memory_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 5. Health Check Status Failure (Platform Health Probe)
resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggered when App Service health check probe indicates unhealthy instances"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
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
