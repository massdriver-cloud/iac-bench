variable "paging_action_group_id" {
  type        = string
  default     = null
  description = "Optional existing Azure Monitor action group to notify on a burst of production server errors."
}

resource "azurerm_monitor_metric_alert" "server_errors" {
  count               = var.paging_action_group_id == null ? 0 : 1
  name                = "${var.app_name}-server-errors"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [azurerm_linux_web_app.service.id]
  description         = "Production returned at least five HTTP 5xx responses in five minutes. Check HTTP and container console logs."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThanOrEqual"
    threshold        = 5
  }
  action {
    action_group_id = var.paging_action_group_id
  }
}
