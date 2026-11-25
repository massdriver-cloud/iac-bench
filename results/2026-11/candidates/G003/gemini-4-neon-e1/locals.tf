locals {
  suffix = var.name_suffix != null ? var.name_suffix : random_string.suffix[0].result

  # Consistent naming respecting Azure resource length and trailing-hyphen limits
  base_name           = "${var.service_name}-${var.environment}"
  resource_group_name = var.resource_group.create ? azurerm_resource_group.this[0].name : var.resource_group.name
  location            = var.resource_group.create ? azurerm_resource_group.this[0].location : var.location

  service_plan_name  = trim(substr("asp-${local.base_name}-${local.suffix}", 0, 40), "-")
  web_app_name       = trim(substr("app-${local.base_name}-${local.suffix}", 0, 60), "-")
  log_analytics_name = trim(substr("log-${local.base_name}-${local.suffix}", 0, 63), "-")
  app_insights_name  = "appi-${local.base_name}-${local.suffix}"
  autoscale_name     = "autoscale-${local.base_name}-${local.suffix}"
  action_group_name  = "ag-${local.base_name}-${local.suffix}"
  action_group_short = substr(replace(var.service_name, "-", ""), 0, 12)

  # Standard SRE metadata tags merged with caller tags
  common_tags = merge(
    {
      service           = var.service_name
      environment       = var.environment
      availability_tier = var.availability.tier
      managed_by        = "opentofu"
    },
    var.tags
  )

  # Capacity & availability translation to App Service Plan internals
  create_service_plan = var.capacity.existing_service_plan_id == null
  service_plan_id     = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id

  sku_map = {
    micro  = "P0v3"
    small  = "P1v3"
    medium = "P2v3"
    large  = "P3v3"
  }
  sku_name = local.sku_map[var.capacity.size]

  zone_redundant = var.availability.tier == "zone_redundant"

  default_min_instances = (
    var.availability.tier == "zone_redundant" ? 3 :
    var.availability.tier == "multi_instance" ? 2 : 1
  )
  min_instances = coalesce(var.capacity.min_instances, local.default_min_instances)

  default_max_instances = (
    var.availability.tier == "zone_redundant" ? min(max(local.min_instances + 6, 9), 30) :
    var.availability.tier == "multi_instance" ? min(max(local.min_instances + 4, 6), 30) :
    local.min_instances
  )
  max_instances = coalesce(var.capacity.max_instances, local.default_max_instances)

  # Scale in multiples of 3 when zone-redundant to keep AZ distribution strictly balanced
  scale_step       = local.zone_redundant ? 3 : 1
  autoscale_active = local.create_service_plan && var.capacity.autoscale_enabled && local.max_instances > local.min_instances

  # Container registry managed identity detection
  is_acr_registry              = can(regex("\\.azurecr\\.io/?$", var.container.registry_url))
  use_managed_identity_for_acr = var.container.use_managed_identity_for_acr != null ? var.container.use_managed_identity_for_acr : local.is_acr_registry

  # Managed identity configuration
  identity_type = length(var.identity.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # Observability wiring
  create_log_analytics       = var.observability.existing_log_analytics_workspace_id == null
  log_analytics_workspace_id = local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.observability.existing_log_analytics_workspace_id

  create_action_group = var.observability.enable_alerts && (
    length(var.observability.alert_email_receivers) > 0 ||
    length(var.observability.alert_webhook_receivers) > 0
  )
  all_action_group_ids = distinct(concat(
    var.observability.action_group_ids,
    local.create_action_group ? [azurerm_monitor_action_group.this[0].id] : []
  ))

  # Rollout & slot configuration
  staging_image                 = coalesce(var.rollouts.staging_image, var.container.image)
  staging_public_access_enabled = coalesce(var.rollouts.staging_public_access_enabled, var.network.public_access_enabled)
  staging_ip_restrictions       = length(var.rollouts.staging_ip_restrictions) > 0 ? var.rollouts.staging_ip_restrictions : var.network.ip_restrictions

  # Platform-managed App Service settings (hidden internals)
  platform_app_settings = {
    WEBSITES_PORT                        = tostring(var.container.port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE  = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT  = tostring(var.health.startup_timeout_seconds)
    WEBSITE_SWAP_WARMUP_PING_PATH        = var.health.path
    WEBSITE_SWAP_WARMUP_PING_STATUSES    = var.health.warmup_statuses
    WEBSITE_SWAP_WARMUP_PING_MAX_RETRIES = tostring(var.health.warmup_max_retries)
    DOCKER_ENABLE_CI                     = "false"
  }

  telemetry_app_settings = var.observability.enable_application_insights ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  } : {}

  key_vault_app_settings = {
    for env_var, secret_uri in var.key_vault_secrets :
    env_var => "@Microsoft.KeyVault(SecretUri=${secret_uri})"
  }

  production_app_settings = merge(
    local.platform_app_settings,
    local.telemetry_app_settings,
    local.key_vault_app_settings,
    var.app_settings,
    {
      APP_SLOT_NAME = "production"
    }
  )

  staging_app_settings = merge(
    local.platform_app_settings,
    local.telemetry_app_settings,
    local.key_vault_app_settings,
    var.app_settings,
    var.rollouts.staging_app_settings,
    {
      APP_SLOT_NAME = var.rollouts.staging_slot_name
    }
  )

  sticky_app_setting_names = distinct(concat(
    ["APP_SLOT_NAME"],
    var.rollouts.sticky_app_setting_names
  ))

  # Diagnostic log categories for containerized Linux App Services
  webapp_diagnostic_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
    "AppServiceAuditLogs",
  ]
}
