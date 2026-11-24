locals {
  common_tags = merge({
    "managed-by" = "opentofu"
    "module"     = "sre-app-service"
  }, var.tags)

  service_plan_id   = var.autoscale_enabled ? azurerm_service_plan.autoscaled[0].id : azurerm_service_plan.manual[0].id
  service_plan_name = var.autoscale_enabled ? azurerm_service_plan.autoscaled[0].name : azurerm_service_plan.manual[0].name

  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  public_network_access_enabled = var.public_network_access_enabled != null ? var.public_network_access_enabled : var.private_endpoint_subnet_id == null

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  default_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT   = tostring(var.container_start_time_limit)
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key
  }

  app_settings = merge(local.default_app_settings, var.app_settings)

  create_action_group = var.alerts_enabled && var.action_group_id == null && length(var.alert_email_receivers) > 0
  action_group_id = var.action_group_id != null ? var.action_group_id : (
    length(var.alert_email_receivers) > 0 ? azurerm_monitor_action_group.this[0].id : null
  )

  availability_test_enabled = var.alerts_enabled && var.availability_test_enabled && local.public_network_access_enabled
}
