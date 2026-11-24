# ------------------------------------------------------------------------------
# Horizontal Autoscaling (Capacity Management)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.capacity.autoscale_enabled ? 1 : 0
  name                = "autoscale-${local.name_prefix}"
  resource_group_name = local.rg_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default-sre-autoscale-profile"

    capacity {
      default = var.capacity.default_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    # Scale Out on sustained high CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThanOrEqual"
        threshold          = var.capacity.cpu_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.scale_out_cooldown_mins}M"
      }
    }

    # Scale Out on sustained high Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThanOrEqual"
        threshold          = var.capacity.memory_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.scale_out_cooldown_mins}M"
      }
    }

    # Scale Out on HTTP queue saturation
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThanOrEqual"
        threshold          = var.capacity.http_queue_scale_out
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.scale_out_cooldown_mins}M"
      }
    }

    # Scale In cautiously on low CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThanOrEqual"
        threshold          = var.capacity.cpu_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.scale_in_cooldown_mins}M"
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Observability: Log Analytics, Application Insights & Diagnostic Settings
# ------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.observability.log_analytics_workspace_id == null ? 1 : 0
  name                = "law-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name = local.rg_name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.retention_in_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_application_insights" "this" {
  count               = var.observability.application_insights_enabled ? 1 : 0
  name                = "appi-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name = local.rg_name
  location            = local.location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.retention_in_days
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "diag-${local.name_prefix}-webapp"
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

  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count                      = var.rollout.staging_slot_enabled ? 1 : 0
  name                       = "diag-${local.name_prefix}-staging"
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

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  name                       = "diag-${local.name_prefix}-plan"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# ------------------------------------------------------------------------------
# SRE Golden Signal Alerts (Errors, Latency, Saturation, Health Check Availability)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count               = var.observability.alerts_enabled && length(var.observability.alert_emails) > 0 ? 1 : 0
  name                = "ag-${local.name_prefix}"
  resource_group_name = local.rg_name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = toset(var.observability.alert_emails)
    content {
      name                    = "sre-${email_receiver.value}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-http5xx"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "High rate of HTTP 5xx server errors on ${azurerm_linux_web_app.this.name}"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.http_5xx_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-latency"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Elevated HTTP response time on ${azurerm_linux_web_app.this.name}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.response_time_threshold_sec
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.observability.alerts_enabled && var.health.probe_alert_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-healthcheck"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "App Service health check status degraded below threshold on ${azurerm_linux_web_app.this.name}"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.health.healthy_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu_saturation" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-cpu-high"
  resource_group_name = local.rg_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Sustained high CPU utilization on App Service Plan ${azurerm_service_plan.this.name}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.cpu_alert_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "memory_saturation" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-memory-high"
  resource_group_name = local.rg_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Sustained high Memory utilization on App Service Plan ${azurerm_service_plan.this.name}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.memory_alert_threshold_pct
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
