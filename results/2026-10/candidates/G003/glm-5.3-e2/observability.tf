# -----------------------------------------------------------------------------
# Observability: one Log Analytics workspace (unless an existing one is
# supplied), workspace-based App Insights for the app and for every slot, and
# diagnostic settings streaming every App Service log category as
# resource-specific tables.
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = var.observability.workspace_id == null ? 1 : 0

  name                = "${var.name}-law"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.retention_in_days
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-ai"
  resource_group_name = local.resource_group_name
  location            = var.location

  workspace_id        = local.workspace_id
  application_type    = "web"
  sampling_percentage = var.observability.app_insights.sampling_percentage
  disable_ip_masking  = var.observability.app_insights.disable_ip_masking
  tags                = var.tags
}

# One component per slot: production telemetry and pre-production telemetry
# never mix, during a rollout or afterwards.
resource "azurerm_application_insights" "slots" {
  for_each = { for slot in var.rollout.slots : slot.name => slot }

  name                = "${var.name}-ai-${each.key}"
  resource_group_name = local.resource_group_name
  location            = var.location

  workspace_id        = local.workspace_id
  application_type    = "web"
  sampling_percentage = var.observability.app_insights.sampling_percentage
  disable_ip_masking  = var.observability.app_insights.disable_ip_masking
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diagnostic_targets

  name                           = "log-analytics"
  target_resource_id             = each.value
  log_analytics_workspace_id     = local.workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "log" {
    for_each = var.observability.log_categories
    content {
      category = log.value
      enabled  = true

      retention_policy {
        enabled = false
      }
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
