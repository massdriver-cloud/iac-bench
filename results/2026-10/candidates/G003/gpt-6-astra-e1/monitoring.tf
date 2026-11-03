resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name}"
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
  # For workspace-based Insights, data retention is controlled by the workspace.
  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                       = "platform-to-workspace"
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
  count                      = var.staging.enabled ? 1 : 0
  name                       = "platform-to-workspace"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "sre" {
  name                = "ag-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "app-sre"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = toset(var.alert_email_addresses)
    content {
      name                    = "email-${substr(sha256(email_receiver.value), 0, 12)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_errors" {
  name                = "alert-${var.name}-http5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Production returned more than 5 HTTP 5xx responses in 5 minutes. Inspect request and container logs."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}

resource "azurerm_monitor_metric_alert" "unhealthy" {
  name                = "alert-${var.name}-health"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "A production instance has sustained unhealthy health checks. Inspect Health Check and container logs."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
    dimension {
      name     = "Instance"
      operator = "Include"
      values   = ["*"]
    }
  }
  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "alert-${var.name}-cpu"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU exceeded 90% over 15 minutes. Check scale ceiling and staging workload before increasing capacity."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }
  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}
