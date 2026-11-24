locals {
  name_prefix = "${var.service_name}-${var.environment}"

  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )

  create_resource_group = var.resource_group_name == null
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  size_to_sku = {
    dev    = "B1"
    small  = "P0v3"
    medium = "P1v3"
    large  = "P2v3"
    xlarge = "P3v3"
  }

  sku_name                = coalesce(var.capacity.sku_name, local.size_to_sku[var.capacity.size])
  is_free_or_shared       = contains(["F1", "D1"], local.sku_name)
  is_basic                = startswith(local.sku_name, "B")
  supports_slots          = !local.is_free_or_shared && !local.is_basic
  supports_autoscale      = !local.is_free_or_shared && !local.is_basic
  supports_always_on      = !local.is_free_or_shared
  supports_zone_balancing = startswith(local.sku_name, "P")

  create_service_plan    = var.capacity.service_plan_id == null
  service_plan_id        = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.service_plan_id
  zone_balancing_enabled = var.availability.zone_redundant && local.supports_zone_balancing
  always_on_enabled      = var.availability.always_on && local.supports_always_on

  staging_slot_enabled = var.rollout.staging_slot_enabled && local.supports_slots
  autoscale_enabled    = local.create_service_plan && var.capacity.autoscale_enabled && local.supports_autoscale && var.capacity.max_instances > var.capacity.min_instances

  scm_use_main_ip_restriction = length(var.availability.ip_restrictions) > 0 || var.availability.ip_restriction_default_action == "Deny"

  # Parse container image into registry URL + repository/tag for App Service application_stack
  image_parts         = split("/", var.container.image)
  image_first_segment = local.image_parts[0]
  has_registry_prefix = length(local.image_parts) > 1 && (
    strcontains(local.image_first_segment, ".") ||
    strcontains(local.image_first_segment, ":") ||
    local.image_first_segment == "localhost"
  )

  docker_registry_url = coalesce(
    var.container.registry_url,
    local.has_registry_prefix ? "https://${local.image_first_segment}" : "https://index.docker.io"
  )

  docker_image_name = local.has_registry_prefix ? join("/", slice(local.image_parts, 1, length(local.image_parts))) : var.container.image

  staging_raw_image   = coalesce(var.rollout.staging_image, var.container.image)
  staging_image_parts = split("/", local.staging_raw_image)
  staging_has_prefix = length(local.staging_image_parts) > 1 && (
    strcontains(local.staging_image_parts[0], ".") ||
    strcontains(local.staging_image_parts[0], ":") ||
    local.staging_image_parts[0] == "localhost"
  )
  staging_docker_image_name = local.staging_has_prefix ? join("/", slice(local.staging_image_parts, 1, length(local.staging_image_parts))) : local.staging_raw_image

  use_managed_identity_for_registry = var.container.use_managed_identity || var.container.acr_id != null

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # Observability wiring
  create_log_analytics = var.observability.enabled && var.observability.log_analytics_workspace_id == null
  has_log_analytics    = var.observability.enabled && (local.create_log_analytics || var.observability.log_analytics_workspace_id != null)
  log_analytics_workspace_id = var.observability.enabled ? (
    local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.observability.log_analytics_workspace_id
  ) : null

  create_app_insights = var.observability.enabled && var.observability.application_insights_id == null
  app_insights_connection_string = var.observability.enabled ? (
    var.observability.application_insights_connection_string != null
    ? var.observability.application_insights_connection_string
    : (local.create_app_insights ? azurerm_application_insights.this[0].connection_string : null)
  ) : null

  create_action_group = var.observability.enabled && var.observability.alerts_enabled && length(var.observability.alert_emails) > 0
  action_group_ids = concat(
    var.observability.action_group_ids,
    local.create_action_group ? [azurerm_monitor_action_group.this[0].id] : []
  )

  warmup_ping_path = try(coalesce(var.rollout.warmup_ping_path, var.health.path), null)

  base_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container.port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DEPLOYMENT_SLOT                     = "production"
    },
    local.warmup_ping_path != null ? {
      WEBSITE_SWAP_WARMUP_PING_PATH     = local.warmup_ping_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES = var.rollout.warmup_ping_statuses
    } : {},
    local.app_insights_connection_string != null ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = local.app_insights_connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    } : {},
    var.app_settings,
    var.secret_app_settings
  )

  staging_app_settings = merge(
    local.base_app_settings,
    {
      DEPLOYMENT_SLOT = var.rollout.slot_name
    },
    var.rollout.staging_app_settings
  )

  sticky_app_setting_names = distinct(concat(
    ["DEPLOYMENT_SLOT"],
    var.rollout.sticky_app_setting_names
  ))
}
