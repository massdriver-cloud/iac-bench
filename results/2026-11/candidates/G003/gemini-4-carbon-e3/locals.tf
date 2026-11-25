locals {
  name_prefix = "${var.service_name}-${var.environment}"

  default_tags = {
    service     = var.service_name
    environment = var.environment
    managed_by  = "opentofu"
  }
  tags = merge(local.default_tags, var.tags)

  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  location            = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location

  app_name = var.custom_app_name != null ? var.custom_app_name : "${substr("app-${local.name_prefix}", 0, 54)}-${random_string.app_suffix[0].result}"

  # SKU capability matrix for Linux App Service Plans
  zone_capable_skus = [
    "P1v2", "P2v2", "P3v2",
    "P0v3", "P1v3", "P2v3", "P3v3",
    "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
    "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
  ]

  slot_capable_skus = [
    "S1", "S2", "S3",
    "P1v2", "P2v2", "P3v2",
    "P0v3", "P1v3", "P2v3", "P3v3",
    "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
    "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
  ]

  create_service_plan = var.capacity.existing_service_plan_id == null
  sku_supports_zones  = contains(local.zone_capable_skus, var.capacity.sku_name)
  sku_supports_slots  = contains(local.slot_capable_skus, var.capacity.sku_name)

  effective_zone_redundant = (
    var.availability.zone_redundant != null
    ? var.availability.zone_redundant
    : (local.sku_supports_zones && var.capacity.min_instances >= 2)
  )

  effective_staging_slot_enabled = (
    var.rollout.staging_slot_enabled != null
    ? var.rollout.staging_slot_enabled
    : (local.create_service_plan ? local.sku_supports_slots : true)
  )

  effective_autoscale_enabled = (
    local.create_service_plan &&
    var.capacity.autoscale_enabled &&
    var.capacity.max_instances > var.capacity.min_instances
  )

  service_plan_id = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id

  # Managed Identity
  has_user_assigned_identities = length(var.user_assigned_identity_ids) > 0
  identity_type                = local.has_user_assigned_identities ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # Health & Warmup
  warmup_path = coalesce(var.health.warmup_path, var.health.path)

  # Observability IDs
  create_log_analytics_workspace = var.observability.existing_log_analytics_workspace_id == null
  log_analytics_workspace_id     = local.create_log_analytics_workspace ? azurerm_log_analytics_workspace.this[0].id : var.observability.existing_log_analytics_workspace_id

  create_action_group = var.observability.alerts_enabled && (
    length(var.observability.alert_email_receivers) > 0 ||
    length(var.observability.alert_webhook_uris) > 0
  )
  effective_action_group_ids = concat(
    var.observability.action_group_ids,
    local.create_action_group ? [azurerm_monitor_action_group.this[0].id] : []
  )

  # Key Vault reference formatting
  formatted_kv_references = {
    for env_key, secret_uri in var.key_vault_secret_references :
    env_key => "@Microsoft.KeyVault(SecretUri=${secret_uri})"
  }

  # Platform-tuned container runtime & warmup settings
  platform_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container.port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = tostring(var.container.enable_storage_mount)
      WEBSITES_CONTAINER_START_TIME_LIMIT = tostring(var.container.startup_time_limit_seconds)
      DOCKER_ENABLE_CI                    = "false"
      WEBSITE_WARMUP_PATH                 = local.warmup_path
      WEBSITE_SWAP_WARMUP_PING_PATH       = local.warmup_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES   = var.health.warmup_statuses
      SERVICE_NAME                        = var.service_name
      SERVICE_ENVIRONMENT                 = var.environment
      OTEL_SERVICE_NAME                   = var.service_name
      OTEL_RESOURCE_ATTRIBUTES            = "service.name=${var.service_name},deployment.environment=${var.environment}"
    },
    var.observability.application_insights_enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    } : {}
  )

  base_app_settings = merge(
    local.platform_app_settings,
    var.app_settings,
    var.secret_app_settings,
    local.formatted_kv_references
  )

  production_app_settings = merge(
    local.base_app_settings,
    {
      APP_DEPLOYMENT_SLOT = "production"
    }
  )

  staging_app_settings = merge(
    local.base_app_settings,
    var.rollout.staging_app_settings,
    {
      APP_DEPLOYMENT_SLOT = "staging"
    }
  )

  sticky_app_setting_names = distinct(concat(
    ["APP_DEPLOYMENT_SLOT"],
    keys(var.rollout.staging_app_settings),
    var.rollout.sticky_app_setting_names
  ))

  web_app_diagnostic_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
  ]

  custom_domains_map = {
    for domain in var.network.custom_domains : domain.hostname => domain
  }
}
