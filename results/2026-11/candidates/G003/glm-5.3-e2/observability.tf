# ---------------------------------------------------------------------------
# Sinks: Log Analytics workspace + Application Insights
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${local.name_prefix}-logs"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  name                = "${local.name_prefix}-insights"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Platform, HTTP, console, audit and platform metrics of both production and
# the staging slot, all in one workspace.
# ---------------------------------------------------------------------------

locals {
  app_service_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs",
  ]
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(local.app_service_log_categories)
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

  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(local.app_service_log_categories)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Paging + alert rules
#
# Every alert fires into the action group, which pages alert_emails. The
# metrics chosen are the ones the front end and the plan emit for Linux
# container apps on every region.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  name                = "${local.name_prefix}-alerts"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = substr(replace(local.name_prefix, "-", ""), 0, 12)
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = tolist(var.alert_emails)
    content {
      name          = "sre-email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
}

# Sev 1: the service is failing requests.
resource "azurerm_monitor_metric_alert" "http_server_errors" {
  name                = "${local.name_prefix}-http-5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "More than 10 HTTP 5xx responses served within 5 minutes. The service is failing requests."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
}

# Sev 2: the fleet is running out of memory. OOM-killed containers are an
# imminent outage: raise max_instances or move to a larger instance_size.
resource "azurerm_monitor_metric_alert" "memory_saturated" {
  name                = "${local.name_prefix}-memory-saturated"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan memory above 80% for 15 minutes: instances are running out of memory. Raise max_instances or instance_size."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
}

# Sev 3: CPU saturation even though autoscaling is active.
resource "azurerm_monitor_metric_alert" "cpu_saturated" {
  name                = "${local.name_prefix}-cpu-saturated"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU above 80% for 15 minutes: autoscaling is not keeping up with load, or max_instances is too low."
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
}
