locals {
  workspace_id = var.log_analytics_workspace_id == null ? azurerm_log_analytics_workspace.service[0].id : var.log_analytics_workspace_id

  web_log_categories = toset([
    "AppServiceConsoleLogs",
    "AppServiceHTTPLogs",
    "AppServicePlatformLogs",
  ])

  # Staging is monitored through logs, but does not page the production team.
  production_alerts = {
    http-5xx = {
      scope       = azurerm_linux_web_app.production.id
      namespace   = "Microsoft.Web/sites"
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = 10
      window      = "PT5M"
      severity    = 2
      description = "Production returned at least 10 HTTP 5xx responses in five minutes."
    }
    unhealthy = {
      scope       = azurerm_linux_web_app.production.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 1
      window      = "PT5M"
      severity    = 2
      description = "An instance reports sustained failed production health checks."
    }
    plan-cpu = {
      scope       = azurerm_service_plan.service.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "CpuPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 85
      window      = "PT15M"
      severity    = 3
      description = "Average CPU across the shared production/staging plan exceeds 85% over 15 minutes."
    }
  }
}

resource "azurerm_log_analytics_workspace" "service" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "${var.name}-logs"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                           = "app-service-logs"
  target_resource_id             = azurerm_linux_web_app.production.id
  log_analytics_workspace_id     = local.workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.web_log_categories
    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.create_staging_slot ? 1 : 0

  name                           = "app-service-logs"
  target_resource_id             = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id     = local.workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.web_log_categories
    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "production" {
  for_each = local.production_alerts

  name                = "${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [each.value.scope]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = each.value.window
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = each.value.namespace
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
    # App Service may take time to start emitting metrics on a new deployment.
    skip_metric_validation = true

    dynamic "dimension" {
      for_each = each.key == "unhealthy" ? ["Instance"] : []
      content {
        name     = dimension.value
        operator = "Include"
        values   = ["*"]
      }
    }
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
