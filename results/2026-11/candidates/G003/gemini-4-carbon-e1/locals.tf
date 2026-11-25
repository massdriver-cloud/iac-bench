locals {
  # ---------------------------------------------------------------------------
  # Resource Placement & Deterministic Naming
  # ---------------------------------------------------------------------------
  create_resource_group = var.existing_resource_group_name == null
  resource_group_name   = local.create_resource_group ? "rg-${var.service_name}-${var.environment}" : var.existing_resource_group_name
  location              = local.create_resource_group ? azurerm_resource_group.this[0].location : var.location

  unique_suffix = substr(
    sha256("${data.azurerm_client_config.current.subscription_id}/${local.resource_group_name}/${var.service_name}/${var.environment}"),
    0,
    6
  )

  service_plan_name     = trim(substr("asp-${var.service_name}-${var.environment}", 0, 60), "-")
  web_app_name          = trim(substr("app-${var.service_name}-${var.environment}-${local.unique_suffix}", 0, 60), "-")
  log_analytics_name    = trim(substr("log-${var.service_name}-${var.environment}-${local.unique_suffix}", 0, 63), "-")
  app_insights_name     = trim(substr("appi-${var.service_name}-${var.environment}", 0, 60), "-")
  autoscale_name        = trim(substr("autoscale-${var.service_name}-${var.environment}", 0, 60), "-")
  private_endpoint_name = trim(substr("pep-${var.service_name}-${var.environment}", 0, 60), "-")

  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )

  # ---------------------------------------------------------------------------
  # Feature & Integration Toggles (Static Plan-Safe Booleans)
  # ---------------------------------------------------------------------------
  create_service_plan  = var.capacity.existing_service_plan_id == null
  service_plan_id      = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id
  create_autoscale     = local.create_service_plan && var.capacity.autoscale_enabled && var.capacity.max_instances > var.capacity.min_instances
  create_log_analytics = var.observability.existing_log_analytics_workspace_id == null
  create_app_insights  = var.observability.application_insights_enabled && var.observability.existing_application_insights_connection_string == null

  log_analytics_workspace_id = local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.observability.existing_log_analytics_workspace_id

  app_insights_connection_string = !var.observability.application_insights_enabled ? null : (
    var.observability.existing_application_insights_connection_string != null
    ? var.observability.existing_application_insights_connection_string
    : azurerm_application_insights.this[0].connection_string
  )

  is_container                  = var.application.container != null
  use_registry_managed_identity = local.is_container ? var.application.container.use_managed_identity : false
  vnet_integrated               = var.network.vnet_integration_subnet_id != null

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  grant_acr_pull_to_system_identity = (
    local.is_container &&
    local.use_registry_managed_identity &&
    (local.is_container ? var.application.container.container_registry_id != null : false) &&
    (local.is_container ? var.application.container.managed_identity_client_id == null : false)
  )

  grant_kv_secrets_to_system_identity = var.key_vault_id != null && var.key_vault_reference_identity_id == null

  # ---------------------------------------------------------------------------
  # Workload Image & Network Defaults
  # ---------------------------------------------------------------------------
  production_docker_image = local.is_container ? "${var.application.container.image}:${var.application.container.tag}" : null
  staging_docker_image    = local.is_container ? "${var.application.container.image}:${coalesce(var.rollout.staging_image_tag, var.application.container.tag)}" : null

  ip_restriction_default_action     = length(var.network.ip_restrictions) > 0 ? "Deny" : "Allow"
  scm_ip_restriction_default_action = length(var.network.scm_ip_restrictions) > 0 ? "Deny" : "Allow"

  # ---------------------------------------------------------------------------
  # App Settings, Key Vault References & Slot-Sticky Pinning
  # ---------------------------------------------------------------------------
  warmup_ping_path = coalesce(var.rollout.warmup_ping_path, var.health.path)

  platform_app_settings = merge(
    {
      PORT                                            = tostring(var.application.port)
      WEBSITES_PORT                                   = tostring(var.application.port)
      WEBSITES_CONTAINER_START_TIME_LIMIT             = tostring(var.health.startup_time_limit_seconds)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE             = tostring(var.application.storage_mounted)
      WEBSITE_WARMUP_PATH                             = local.warmup_ping_path
      WEBSITE_SWAP_WARMUP_PING_PATH                   = local.warmup_ping_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES               = var.rollout.warmup_expected_statuses
      WEBSITE_ADD_SITENAME_BINDINGS_IN_APPHOST_CONFIG = "1"
    },
    local.is_container ? { DOCKER_ENABLE_CI = "false" } : {}
  )

  telemetry_app_settings = var.observability.application_insights_enabled ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING      = local.app_insights_connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    OTEL_SERVICE_NAME                          = var.service_name
    OTEL_RESOURCE_ATTRIBUTES                   = "service.name=${var.service_name},deployment.environment=${var.environment}"
  } : {}

  key_vault_app_settings = {
    for env_name, secret_ref in var.key_vault_secrets :
    env_name => startswith(secret_ref, "@Microsoft.KeyVault(") ? secret_ref : "@Microsoft.KeyVault(SecretUri=${secret_ref})"
  }

  production_app_settings = merge(
    local.platform_app_settings,
    local.telemetry_app_settings,
    var.app_settings,
    local.key_vault_app_settings,
    {
      DEPLOYMENT_SLOT = "production"
    }
  )

  staging_app_settings = merge(
    local.platform_app_settings,
    local.telemetry_app_settings,
    var.app_settings,
    local.key_vault_app_settings,
    var.rollout.staging_app_settings,
    {
      DEPLOYMENT_SLOT = "staging"
    }
  )

  connection_string_keys = nonsensitive(toset(keys(var.connection_strings)))

  sticky_app_setting_names = distinct(concat(
    ["DEPLOYMENT_SLOT"],
    keys(var.rollout.staging_app_settings),
    var.rollout.slot_sticky_app_setting_names
  ))

  sticky_connection_string_names = distinct(concat(
    [for k in local.connection_string_keys : k if nonsensitive(var.connection_strings[k].slot_sticky)],
    var.rollout.slot_sticky_connection_string_names
  ))

  web_app_diagnostic_log_categories = toset([
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs",
  ])
}
