resource "random_string" "suffix" {
  count   = var.name_suffix == null ? 1 : 0
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix      = var.name_suffix != null ? var.name_suffix : random_string.suffix[0].result
  name_base   = "${var.service_name}-${var.environment}"
  unique_base = local.suffix != "" ? "${local.name_base}-${local.suffix}" : local.name_base

  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  manage_service_plan = var.capacity.existing_service_plan_id == null
  service_plan_id     = local.manage_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id

  app_name                = "app-${local.unique_base}"
  service_plan_name       = "asp-${local.name_base}"
  autoscale_name          = "as-${local.name_base}"
  log_analytics_name      = "law-${local.unique_base}"
  app_insights_name       = "appi-${local.name_base}"
  action_group_name       = "ag-${local.name_base}"
  action_group_short_name = substr(replace("ag${var.service_name}", "-", ""), 0, 12)
  synthetic_web_test_name = "wt-${local.name_base}"
  default_resource_group  = "rg-${local.unique_base}"

  autoscale_enabled = local.manage_service_plan && var.capacity.autoscale.enabled
  scale_step        = var.capacity.zone_redundant ? "3" : "1"
  cooldown_iso8601  = "PT${var.capacity.autoscale.cooldown_minutes}M"

  use_acr_managed_identity = (
    var.container.use_managed_identity != null
    ? var.container.use_managed_identity
    : (var.container.acr_id != null || can(regex("\\.azurecr\\.io/?$", lower(var.container.registry_url))))
  )

  warmup_path = coalesce(var.rollout.warmup_path, var.health.path)

  identity_type = length(var.security.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
  identity_ids  = length(var.security.user_assigned_identity_ids) > 0 ? var.security.user_assigned_identity_ids : null

  key_vault_secret_app_settings = {
    for k, uri in var.security.key_vault_secrets :
    k => "@Microsoft.KeyVault(SecretUri=${uri})"
  }

  log_analytics_workspace_id = (
    var.observability.enabled
    ? (
      var.observability.existing_log_analytics_workspace_id != null
      ? var.observability.existing_log_analytics_workspace_id
      : azurerm_log_analytics_workspace.this[0].id
    )
    : null
  )

  synthetic_probe_enabled = (
    var.observability.enabled &&
    var.health.synthetic_probe.enabled &&
    var.networking.public_network_access_enabled
  )

  alerts_enabled = var.observability.enabled && var.observability.alerts.enabled

  create_action_group = (
    local.alerts_enabled &&
    (length(var.observability.alerts.email_receivers) > 0 || length(var.observability.alerts.webhook_receivers) > 0)
  )

  action_group_ids = concat(
    var.observability.alerts.existing_action_group_ids,
    local.create_action_group ? [azurerm_monitor_action_group.this[0].id] : []
  )

  platform_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container.port)
      WEBSITES_CONTAINER_START_TIME_LIMIT = tostring(var.container.startup_timeout_seconds)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = tostring(var.container.enable_persistent_storage)
      DOCKER_ENABLE_CI                    = "false"
      WEBSITE_HEALTHCHECK_MAXPINGFAILURES = tostring(var.health.max_ping_failures)
      WEBSITE_SWAP_WARMUP_PING_PATH       = local.warmup_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES   = var.rollout.warmup_statuses
      OTEL_SERVICE_NAME                   = var.service_name
    },
    var.observability.enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    } : {},
    local.key_vault_secret_app_settings
  )

  production_app_settings = merge(
    local.platform_app_settings,
    {
      DEPLOYMENT_SLOT          = "production"
      OTEL_RESOURCE_ATTRIBUTES = "deployment.environment=${var.environment},service.slot=production"
    },
    var.app_settings,
    var.sensitive_app_settings
  )

  staging_app_settings = merge(
    local.platform_app_settings,
    {
      DEPLOYMENT_SLOT          = var.rollout.staging_slot_name
      OTEL_RESOURCE_ATTRIBUTES = "deployment.environment=${var.environment},service.slot=${var.rollout.staging_slot_name}"
    },
    var.app_settings,
    var.rollout.staging_app_settings,
    var.sensitive_app_settings
  )

  sticky_app_setting_names = distinct(concat(
    [
      "DEPLOYMENT_SLOT",
      "OTEL_RESOURCE_ATTRIBUTES"
    ],
    var.rollout.sticky_app_setting_names
  ))

  web_app_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs"
  ]

  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )
}
