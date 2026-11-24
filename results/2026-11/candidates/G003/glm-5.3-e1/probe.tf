# -----------------------------------------------------------------------------
# Active health probes: the module's baseline alerting layer.
#
# These continuously probe the running service - HTTP server errors, health
# check score, plan CPU - and page when the service degrades. Delivery goes to
# the module's own action group (email) and/or existing action groups.
# Everything here is created only when there is somewhere to deliver alerts
# (alert_emails and/or action_group_ids), so a bare instantiation stays
# dormant instead of alerting into the void.
# -----------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count = length(var.alert_emails) > 0 ? 1 : 0

  name                = "${var.name}-oncall"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)

  dynamic "email_receiver" {
    for_each = toset(var.alert_emails)
    content {
      name                    = substr("email-${replace(email_receiver.value, "/[^a-zA-Z0-9_-]/", "")}", 0, 100)
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_server_errors" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-http-server-errors"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "More than ${var.alert_thresholds.http_5xx_per_5m} HTTP 5xx responses from ${var.name} in 5 minutes."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_thresholds.http_5xx_per_5m
  }

  dynamic "action" {
    for_each = toset(var.action_group_ids)
    content {
      action_group_id = action.value
    }
  }

  dynamic "action" {
    for_each = length(var.alert_emails) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.this[0].id
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average health check score for ${var.name} fell below ${var.alert_thresholds.health_score}: at least one instance is failing probes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.alert_thresholds.health_score
  }

  dynamic "action" {
    for_each = toset(var.action_group_ids)
    content {
      action_group_id = action.value
    }
  }

  dynamic "action" {
    for_each = length(var.alert_emails) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.this[0].id
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu_saturation" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-cpu-saturation"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU above ${var.alert_thresholds.cpu_percent}% for 15 minutes: the service is out of headroom or pinned at max_instances."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/serverFarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_thresholds.cpu_percent
  }

  dynamic "action" {
    for_each = toset(var.action_group_ids)
    content {
      action_group_id = action.value
    }
  }

  dynamic "action" {
    for_each = length(var.alert_emails) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.this[0].id
    }
  }
}
