variable "staging_image" {
  description = "Image to deploy to staging, in the same registry as production. Null uses the production image."
  type        = string
  default     = null
  validation {
    condition     = var.staging_image == null ? true : length(trimspace(var.staging_image)) > 0
    error_message = "staging_image must be null or a nonempty image name."
  }
}

variable "alert_action_group_ids" {
  description = "Azure Monitor action group IDs to notify on sustained HTTP 5xx errors. Empty creates an alert without notifications."
  type        = set(string)
  default     = []
}

resource "azurerm_monitor_metric_alert" "server_errors" {
  name                = "${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [azurerm_linux_web_app.service.id]
  description         = "More than 10 HTTP 5xx responses in five minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
