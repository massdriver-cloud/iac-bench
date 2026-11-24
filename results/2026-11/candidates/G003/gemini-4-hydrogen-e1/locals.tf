locals {
  name_prefix         = "${var.service_name}-${var.environment}"
  resource_group_name = coalesce(var.resource_group_name, "rg-${local.name_prefix}")
  web_app_name        = coalesce(var.web_app_name, "app-${local.name_prefix}")

  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags,
  )

  # Capability checks derived from the selected App Service Plan SKU
  sku_upper           = upper(var.capacity.sku_name)
  is_free_or_shared   = contains(["F1", "D1"], local.sku_upper)
  is_basic            = startswith(local.sku_upper, "B")
  is_standard_or_high = !local.is_free_or_shared && !local.is_basic
  is_premium          = startswith(local.sku_upper, "P")

  supports_always_on = !local.is_free_or_shared
  supports_slots     = local.is_standard_or_high
  supports_autoscale = local.is_standard_or_high
  supports_zone_bal  = local.is_premium

  effective_always_on = local.supports_always_on ? var.availability.always_on : false
  effective_slots     = local.supports_slots && var.rollout.staging_slot_enabled
  effective_autoscale = local.supports_autoscale && var.capacity.autoscale_enabled

  effective_worker_count = (
    var.availability.zone_redundant && var.capacity.default_instances < 3
    ? 3
    : var.capacity.default_instances
  )

  effective_min_instances = (
    var.availability.zone_redundant && var.capacity.min_instances < 3
    ? 3
    : var.capacity.min_instances
  )

  effective_max_instances = max(var.capacity.max_instances, local.effective_min_instances)

  # Observability wiring
  create_log_analytics = (
    (var.observability.diagnostic_logs_enabled || var.observability.app_insights_enabled)
    && var.observability.log_analytics_workspace_id == null
  )

  log_analytics_workspace_id = (
    var.observability.log_analytics_workspace_id != null
    ? var.observability.log_analytics_workspace_id
    : (local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : null)
  )

  # Standard App Service container & SRE platform settings
  base_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container.port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = tostring(var.container.storage_mount_enabled)
      WEBSITES_CONTAINER_START_TIME_LIMIT = tostring(var.container.startup_timeout_seconds)
      WEBSITE_SWAP_WARMUP_PING_PATH       = var.health.path
      WEBSITE_SWAP_WARMUP_PING_STATUSES   = var.health.warmup_statuses
      APP_ENVIRONMENT                     = var.environment
      SERVICE_NAME                        = var.service_name
    },
    var.observability.app_insights_enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[0].connection_string
    } : {},
    var.app_settings,
  )

  sticky_app_setting_names = distinct(concat(
    ["APP_SLOT", "WEBSITE_SWAP_WARMUP_PING_PATH"],
    var.rollout.sticky_app_setting_names,
  ))

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
}
