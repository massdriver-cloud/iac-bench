resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name}-logs"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "main" {
  name                = "${var.name}-insights"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = 30
  tags                = local.tags
}

locals {
  monitored_apps = merge({ production = azurerm_linux_web_app.main.id }, var.staging_enabled ? { staging = azurerm_linux_web_app_slot.staging[0].id } : {})
  alerts = {
    server_errors = {
      scope       = azurerm_linux_web_app.main.id
      namespace   = "Microsoft.Web/sites"
      metric      = "Http5xx"
      aggregation = "Total"
      threshold   = 10
      severity    = 1
      description = "More than 10 production HTTP 5xx responses in five minutes."
    }
    latency = {
      scope       = azurerm_linux_web_app.main.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HttpResponseTime"
      aggregation = "Average"
      threshold   = var.response_time_threshold_seconds
      severity    = 2
      description = "High average production HTTP response time."
    }
    cpu = {
      scope       = local.service_plan_id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "CpuPercentage"
      aggregation = "Average"
      threshold   = 85
      severity    = 2
      description = "High plan CPU; inspect load and autoscale maximum."
    }
    memory = {
      scope       = local.service_plan_id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "MemoryPercentage"
      aggregation = "Average"
      threshold   = 85
      severity    = 2
      description = "High plan memory; inspect leaks or increase plan size."
    }
    health = {
      scope       = azurerm_linux_web_app.main.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      threshold   = 1
      severity    = 1
      description = "Production health-check status averages below healthy (1) over five minutes."
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "apps" {
  for_each                   = local.monitored_apps
  name                       = "central-logs"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServicePlatformLogs" }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_action_group" "sre" {
  name                = "${var.name}-sre"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "app-sre"
  tags                = local.tags
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${substr(sha256(email_receiver.value), 0, 12)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "main" {
  for_each            = local.alerts
  name                = "${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [each.value.scope]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true
  tags                = local.tags
  criteria {
    metric_namespace = each.value.namespace
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.key == "health" ? "LessThan" : "GreaterThan"
    threshold        = each.value.threshold
  }
  action { action_group_id = azurerm_monitor_action_group.sre.id }
}
