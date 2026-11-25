variable "alert_action_group_ids" {
  description = "Existing Azure Monitor action group IDs to notify on sustained HTTP 5xx errors. Empty creates the alert without notifications."
  type        = set(string)
  default     = []
}

variable "http_5xx_alert_threshold" {
  description = "Alert when the production app returns more than this many 5xx responses in five minutes."
  type        = number
  default     = 10
  validation {
    condition     = var.http_5xx_alert_threshold >= 0
    error_message = "http_5xx_alert_threshold must be non-negative."
  }
}

variable "staging_app_settings" {
  description = "Settings that override app_settings on the staging slot. Mark environment-specific keys sticky in slot_sticky_setting_names."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "slot_sticky_setting_names" {
  description = "Application setting names that must stay with their slot during a swap."
  type        = list(string)
  default     = []
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [azurerm_linux_web_app.service.id]
  description         = "Production app is returning elevated HTTP 5xx responses."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.http_5xx_alert_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
