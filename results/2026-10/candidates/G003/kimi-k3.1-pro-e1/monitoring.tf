resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = local.workspace_name
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                 = local.app_insights_name
  resource_group_name  = local.resource_group_name
  location             = var.location
  workspace_id         = local.log_analytics_workspace_id
  application_type     = "web"
  retention_in_days    = var.log_retention_days
  daily_data_cap_in_gb = var.application_insights_daily_cap_gb
  sampling_percentage  = var.application_insights_sampling_percentage
  tags                 = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                       = substr("${var.name}-production-diagnostics", 0, 260)
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

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.deployment_slot_enabled ? 1 : 0

  name                       = substr("${var.name}-staging-diagnostics", 0, 260)
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

resource "azurerm_monitor_action_group" "this" {
  count = length(var.alert_email_receivers) > 0 ? 1 : 0

  name                = local.action_group_name
  resource_group_name = local.resource_group_name
  short_name          = substr("sre-${var.name}", 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = { for index, email in var.alert_email_receivers : tostring(index) => email }
    content {
      name                    = "sre-email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "standard" {
  for_each = local.metric_alerts

  name                = substr("${var.name}-${each.key}", 0, 260)
  resource_group_name = local.resource_group_name
  scopes              = [each.value.scope_id]
  description         = each.value.description
  severity            = each.value.severity
  enabled             = var.alerts_enabled
  frequency           = each.value.frequency
  window_size         = each.value.window_size
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = each.value.metric_namespace
    metric_name      = each.value.metric_name
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = local.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_application_insights_standard_web_test" "health" {
  count = local.availability_test_active ? 1 : 0

  name                    = substr("${var.name}-health", 0, 250)
  resource_group_name     = local.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id
  geo_locations           = var.availability_test_geo_locations
  frequency               = 300
  timeout                 = 30
  retry_enabled           = true
  enabled                 = true
  tags                    = local.tags

  request {
    url = "https://${azurerm_linux_web_app.this.default_hostname}${var.health_check_path}"
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  count = local.availability_test_active ? 1 : 0

  name                = substr("${var.name}-availability", 0, 260)
  resource_group_name = local.resource_group_name
  scopes = [
    azurerm_application_insights.this.id,
    azurerm_application_insights_standard_web_test.health[0].id,
  ]
  description   = "External health-test availability fell below the configured 15-minute percentage."
  severity      = 1
  enabled       = var.alerts_enabled
  frequency     = "PT5M"
  window_size   = "PT15M"
  auto_mitigate = true
  tags          = local.tags

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.availability_alert_threshold
  }

  dynamic "action" {
    for_each = local.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
