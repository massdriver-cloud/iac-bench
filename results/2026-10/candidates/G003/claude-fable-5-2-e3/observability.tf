###############################################################################
# Logs and traces
###############################################################################

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "log-${local.base_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

# Workspace-based Application Insights. The connection string is injected into
# the container as APPLICATIONINSIGHTS_CONNECTION_STRING, which the Azure
# Monitor OpenTelemetry distros and Application Insights SDKs pick up.
resource "azurerm_application_insights" "this" {
  name                = "appi-${local.base_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  tags                = local.tags
}

# Platform logs: HTTP access log, container stdout/stderr, platform events
# (container starts, pulls, health evictions) and access audit logs.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${local.base_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.log_categories

    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name                       = "diag-${local.base_name}-${local.slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.log_categories

    content {
      category = enabled_log.value
    }
  }
}

###############################################################################
# Alerts
###############################################################################

resource "azurerm_monitor_action_group" "email" {
  count = length(var.alert_email_addresses) > 0 ? 1 : 0

  name                = "ag-${local.base_name}"
  resource_group_name = local.resource_group_name
  short_name          = substr(var.name, 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses

    content {
      name                    = "email-${email_receiver.key + 1}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = local.metric_alerts

  name                = "alert-${local.base_name}-${each.key}"
  resource_group_name = local.resource_group_name
  description         = each.value.description
  severity            = each.value.severity
  enabled             = true
  auto_mitigate       = true
  frequency           = each.value.frequency
  window_size         = each.value.window

  scopes = [
    each.value.target == "plan" ? azurerm_service_plan.this.id : azurerm_linux_web_app.this.id
  ]

  criteria {
    metric_namespace = each.value.target == "plan" ? "Microsoft.Web/serverfarms" : "Microsoft.Web/sites"
    metric_name      = each.value.metric
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

  tags = local.tags
}
