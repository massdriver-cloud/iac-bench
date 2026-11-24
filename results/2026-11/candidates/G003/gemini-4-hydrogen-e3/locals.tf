locals {
  name_prefix         = "${var.service_name}-${var.environment}"
  resource_group_name = coalesce(var.resource_group_name, "rg-${local.name_prefix}")

  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )

  sku_profile_map = {
    dev          = "B1"
    basic        = "S1"
    standard     = "P1v3"
    compute      = "P2v3"
    high_compute = "P3v3"
    memory       = "P1mv3"
  }

  sku_name                 = coalesce(var.capacity.sku_name, local.sku_profile_map[var.capacity.profile])
  is_free_or_basic         = contains(["F1", "D1", "B1", "B2", "B3"], local.sku_name)
  supports_slots           = !local.is_free_or_basic
  supports_autoscale       = !local.is_free_or_basic
  supports_zone_redundancy = can(regex("^P[1-5]m?v[23]$", local.sku_name))

  create_service_plan = var.capacity.existing_service_plan_id == null
  always_on           = contains(["F1", "D1"], local.sku_name) ? false : var.capacity.always_on
  enable_staging_slot = var.rollout.enable_staging_slot != null ? var.rollout.enable_staging_slot : local.supports_slots
  autoscale_enabled   = local.create_service_plan && local.supports_autoscale && var.capacity.max_instances > var.capacity.min_instances

  identity_ids = distinct(compact(concat(
    var.user_assigned_identity_ids,
    [var.container_registry.managed_identity_id]
  )))
  identity_type = length(local.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  create_log_analytics       = var.observability.enabled && var.observability.log_analytics_workspace_id == null
  log_analytics_workspace_id = local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.observability.log_analytics_workspace_id
  create_app_insights        = var.observability.enabled && var.observability.enable_application_insights
  create_diagnostics         = var.observability.enabled && var.observability.enable_diagnostic_settings && (local.create_log_analytics || var.observability.log_analytics_workspace_id != null)
  create_alerts              = var.observability.enabled && var.observability.enable_alerts

  base_app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = tostring(var.container_port)
    WEBSITES_CONTAINER_START_TIME_LIMIT = tostring(var.container_start_timeout_seconds)
    WEBSITES_CONTAINER_STOP_TIME_LIMIT  = tostring(var.rollout.graceful_shutdown_seconds)
    SERVICE_NAME                        = var.service_name
    SERVICE_ENVIRONMENT                 = var.environment
  }

  health_app_settings = var.health_check.path != null ? {
    WEBSITE_HEALTHCHECK_MAXPINGFAILURES = tostring(var.health_check.max_ping_failures)
    WEBSITE_SWAP_WARMUP_PING_PATH       = var.health_check.path
    WEBSITE_SWAP_WARMUP_PING_STATUSES   = var.rollout.warmup_ping_statuses
  } : {}

  app_insights_settings = local.create_app_insights ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  } : {}

  prod_app_settings = merge(
    local.base_app_settings,
    local.health_app_settings,
    local.app_insights_settings,
    var.app_settings,
    var.secret_app_settings,
    {
      DEPLOYMENT_SLOT = "production"
    }
  )

  staging_app_settings = merge(
    local.base_app_settings,
    local.health_app_settings,
    local.app_insights_settings,
    var.app_settings,
    var.secret_app_settings,
    var.rollout.staging_app_settings,
    {
      DEPLOYMENT_SLOT = "staging"
    }
  )

  sticky_app_setting_names = distinct(concat(
    ["DEPLOYMENT_SLOT"],
    var.rollout.sticky_app_setting_names
  ))

  staging_container_image = coalesce(var.rollout.staging_container_image, var.container_image)
}
