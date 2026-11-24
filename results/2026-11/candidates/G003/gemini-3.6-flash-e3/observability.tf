# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "law" {
  count               = var.enable_observability && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "law-${var.name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

locals {
  effective_log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : (
    var.enable_observability ? azurerm_log_analytics_workspace.law[0].id : null
  )
}

# Application Insights
resource "azurerm_application_insights" "app" {
  count               = var.enable_observability && var.application_insights_id == null ? 1 : 0
  name                = "appi-${var.name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  application_type    = "web"
  workspace_id        = local.effective_log_analytics_workspace_id
  tags                = var.tags
}

# Diagnostic Settings for App Service
resource "azurerm_monitor_diagnostic_setting" "app_diag" {
  count                      = var.enable_observability ? 1 : 0
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.app.id
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

# Diagnostic Settings for Staging Slot
resource "azurerm_monitor_diagnostic_setting" "staging_diag" {
  count                      = var.enable_observability && var.enable_staging_slot ? 1 : 0
  name                       = "diag-${var.name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
