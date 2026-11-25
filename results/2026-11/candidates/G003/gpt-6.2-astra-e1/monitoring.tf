resource "azurerm_log_analytics_workspace" "service" {
  name                = "${var.app_name}-logs"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

locals {
  monitored_apps = merge({ production = azurerm_linux_web_app.service.id }, { for slot in azurerm_linux_web_app_slot.staging : "staging" => slot.id })
}

resource "azurerm_monitor_diagnostic_setting" "apps" {
  for_each                   = local.monitored_apps
  name                       = "service-telemetry"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServicePlatformLogs" }
  enabled_metric { category = "AllMetrics" }
}
