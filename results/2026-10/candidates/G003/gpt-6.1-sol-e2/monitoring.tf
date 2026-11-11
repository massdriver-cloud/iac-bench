resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-logs"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-insights"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "central-logs"
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
  count                      = var.staging_enabled ? 1 : 0
  name                       = "central-logs"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "${var.name}-autoscale"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  target_resource_id  = azurerm_service_plan.this.id
  tags                = var.tags

  profile {
    name = "cpu"
    capacity {
      minimum = tostring(var.capacity.minimum)
      maximum = tostring(var.capacity.maximum)
      default = tostring(var.capacity.initial)
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
        threshold          = 70
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
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

resource "azurerm_monitor_action_group" "this" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "${var.name}-oncall"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "sre-oncall"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${substr(sha256(email_receiver.value), 0, 12)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_errors" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "At least 10 HTTP 5xx responses over five minutes in production."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThanOrEqual"
    threshold        = 10
  }
  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }
}

resource "azurerm_monitor_metric_alert" "health" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "${var.name}-unhealthy"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average production health-check status below 100 percent over five minutes."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }
  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }
}
