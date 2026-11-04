locals {
  # --- naming / tagging -------------------------------------------------------
  tags = merge({ "service" = var.name, "managed-by" = "opentofu" }, var.tags)

  # --- capacity / availability ------------------------------------------------
  # Zone balancing requires a minimum of 3 instances; raise silently so the SRE
  # does not have to keep two knobs in sync.
  capacity = var.zone_redundant ? max(var.capacity, 3) : var.capacity

  autoscale_min     = var.zone_redundant ? max(var.autoscale.minimum, 3) : var.autoscale.minimum
  autoscale_max     = max(var.autoscale.maximum, local.autoscale_min)
  autoscale_default = min(max(var.autoscale.default_capacity, local.autoscale_min), local.autoscale_max)

  # --- rollouts ---------------------------------------------------------------
  slot_enabled = var.deployment_slot.enabled
  slot_name    = var.deployment_slot.name

  # --- health -----------------------------------------------------------------
  health_check_eviction_time_in_min = var.health_check_path != null ? var.health_check_eviction_time_in_minutes : null
  health_probe_path                 = var.health_check_path != null ? var.health_check_path : "/"

  # --- observability ----------------------------------------------------------
  # A workspace is needed when the SRE did not bring one but either Application
  # Insights (workspace-based) or diagnostic settings are on.
  observability_needs_workspace = var.application_insights_enabled || var.diagnostic_logs_enabled
  create_workspace              = var.log_analytics_workspace_id == null && local.observability_needs_workspace
  log_analytics_workspace_id    = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : try(azurerm_log_analytics_workspace.main[0].id, null)

  availability_test_enabled = var.application_insights_enabled && var.availability_test.enabled

  # --- app settings -----------------------------------------------------------
  monitoring_app_settings = var.application_insights_enabled ? {
    APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.main[0].instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.main[0].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  } : {}

  container_app_settings = merge(
    var.container.port != null ? { WEBSITES_PORT = tostring(var.container.port) } : {},
    var.container.use_managed_identity && var.vnet_integration_subnet_id != null ? { WEBSITE_PULL_IMAGE_OVER_VNET = "true" } : {},
  )

  # User-provided settings win on conflict - SREs stay in control.
  app_settings = merge(local.monitoring_app_settings, local.container_app_settings, var.app_settings)

  # --- alerts -----------------------------------------------------------------
  action_group_ids = concat(
    [for ag in azurerm_monitor_action_group.email : ag.id],
    var.alerts.action_group_ids,
  )

  diagnostic_log_categories = toset([
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditEvents",
    "AppServicePlatformLogs",
  ])
}
