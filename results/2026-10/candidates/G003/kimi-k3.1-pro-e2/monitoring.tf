resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "${var.name}-law"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_in_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-appi"
  resource_group_name = var.resource_group_name
  location            = var.location
  application_type    = "web"
  workspace_id        = local.log_analytics_workspace_id
  sampling_percentage = var.application_insights_sampling_percentage
  tags                = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                           = "${var.name}-production-diag"
  target_resource_id             = azurerm_linux_web_app.this.id
  log_analytics_workspace_id     = local.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

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

  name                           = "${var.name}-staging-diag"
  target_resource_id             = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id     = local.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

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

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  name                       = "${var.name}-plan-diag"
  target_resource_id         = local.service_plan_id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "this" {
  count = local.create_action_group ? 1 : 0

  name                = "${var.name}-sre-alerts"
  resource_group_name = var.resource_group_name
  location            = "Global"
  short_name          = substr(var.name, 0, 12)
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-http-5xx"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Production returned more than the configured number of HTTP 5xx responses in five minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.http_5xx_alert_threshold
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "unhealthy_instances" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-health-check"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "At least one production instance is failing the App Service health check."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "sustained_cpu" {
  count = var.alerts_enabled ? 1 : 0

  name                = "${var.name}-sustained-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [local.service_plan_id]
  description         = "Plan CPU has remained above the configured threshold for fifteen minutes; inspect autoscale and service capacity."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_application_insights_standard_web_test" "health" {
  count = local.availability_test_enabled ? 1 : 0

  name                    = "${var.name}-external-health"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id
  enabled                 = true
  frequency               = 300
  timeout                 = 30
  retry_enabled           = true
  geo_locations           = var.availability_test_geo_locations
  tags                    = local.common_tags

  request {
    url                              = "https://${azurerm_linux_web_app.this.default_hostname}${var.health_check_path}"
    http_verb                        = "GET"
    follow_redirects_enabled         = true
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
  }
}

resource "azurerm_monitor_metric_alert" "external_availability" {
  count = local.availability_test_enabled ? 1 : 0

  name                = "${var.name}-external-availability"
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.health[0].id,
    azurerm_application_insights.this.id
  ]
  description   = "External health probes are failing or returning non-200 responses from the configured test locations."
  severity      = 1
  frequency     = "PT1M"
  window_size   = "PT5M"
  auto_mitigate = true
  tags          = local.common_tags

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.availability_alert_threshold
  }

  dynamic "action" {
    for_each = local.action_group_id == null ? [] : [local.action_group_id]
    content {
      action_group_id = action.value
    }
  }
}
