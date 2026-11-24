resource "random_string" "suffix" {
  count   = var.use_random_name_suffix ? 1 : 0
  length  = 6
  upper   = false
  special = false
}

locals {
  base_name   = "${var.name}-${var.environment}"
  name_suffix = var.use_random_name_suffix ? "-${random_string.suffix[0].result}" : ""

  resource_group_name = coalesce(
    var.resource_group_name,
    "rg-${local.base_name}"
  )

  # Enforce Azure resource name length limits cleanly while preserving suffix uniqueness
  web_app_name = "${replace(substr("app-${local.base_name}", 0, 60 - length(local.name_suffix)), "/-+$/", "")}${local.name_suffix}"
  plan_name    = replace(substr("plan-${local.base_name}", 0, 40), "/-+$/", "")
  law_name     = "${replace(substr("log-${local.base_name}", 0, 63 - length(local.name_suffix)), "/-+$/", "")}${local.name_suffix}"
  appi_name    = replace(substr("appi-${local.base_name}", 0, 60), "/-+$/", "")
  ag_name      = replace(substr("ag-${local.base_name}", 0, 60), "/-+$/", "")
  ag_short     = substr(replace("sre${var.name}", "-", ""), 0, 12)

  common_tags = merge(
    {
      service     = var.name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )

  # ---------------------------------------------------------------------------
  # Plan & SKU Capabilities
  # ---------------------------------------------------------------------------
  create_service_plan = var.capacity.existing_service_plan_id == null
  service_plan_id     = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id

  is_free_sku  = var.capacity.sku_name == "F1"
  is_basic_sku = startswith(var.capacity.sku_name, "B")

  sku_supports_always_on = !local.create_service_plan || !local.is_free_sku
  sku_supports_slots     = !local.create_service_plan || (!local.is_free_sku && !local.is_basic_sku)
  sku_supports_autoscale = !local.create_service_plan || (!local.is_free_sku && !local.is_basic_sku)
  sku_supports_zones = !local.create_service_plan || (
    !local.is_free_sku &&
    !local.is_basic_sku &&
    !startswith(var.capacity.sku_name, "S") &&
    !contains(["P0v3", "P0v4"], var.capacity.sku_name)
  )

  always_on_effective    = local.sku_supports_always_on ? var.availability.always_on : false
  staging_slot_enabled   = var.rollout.staging_slot_enabled
  autoscale_enabled      = local.create_service_plan && var.capacity.autoscale.enabled && var.capacity.max_instances > var.capacity.min_instances
  use_acr_managed_id     = var.container.use_managed_identity_auth || var.container.acr_id != null
  identity_type          = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
  vnet_image_pull_active = coalesce(var.networking.vnet_image_pull_enabled, var.networking.vnet_integration_subnet_id != null)

  # ---------------------------------------------------------------------------
  # Observability Toggles
  # ---------------------------------------------------------------------------
  observability_enabled   = var.observability.enabled
  create_log_analytics    = local.observability_enabled && var.observability.existing_log_analytics_workspace_id == null
  log_analytics_id        = local.observability_enabled ? (local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.observability.existing_log_analytics_workspace_id) : null
  app_insights_enabled    = local.observability_enabled && var.observability.application_insights_enabled
  diagnostic_logs_enabled = local.observability_enabled && var.observability.diagnostic_logs_enabled
  alerts_enabled          = local.observability_enabled && var.observability.alerts.enabled
  create_action_group     = local.alerts_enabled && length(var.observability.alert_emails) > 0

  # Keep list length statically known at plan time even when azurerm_monitor_action_group.this[0].id is unknown
  effective_action_group_ids = concat(
    distinct(var.observability.action_group_ids),
    local.create_action_group ? [azurerm_monitor_action_group.this[0].id] : []
  )

  # ---------------------------------------------------------------------------
  # App Service Internal Settings & Secrets Wiring
  # ---------------------------------------------------------------------------
  warmup_app_settings = var.health.path != null ? {
    WEBSITE_WARMUP_PATH               = var.health.path
    WEBSITE_SWAP_WARMUP_PING_PATH     = var.health.path
    WEBSITE_SWAP_WARMUP_PING_STATUSES = var.health.warmup_valid_status_codes
  } : {}

  telemetry_app_settings = local.app_insights_enabled ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  } : {}

  platform_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container.port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = tostring(var.container.enable_persistent_storage)
      WEBSITES_CONTAINER_START_TIME_LIMIT = tostring(var.health.startup_timeout_seconds)
      DOCKER_ENABLE_CI                    = "false"
    },
    local.warmup_app_settings,
    local.telemetry_app_settings
  )

  key_vault_app_settings = {
    for env_key, secret_uri in var.key_vault_secret_uris :
    env_key => "@Microsoft.KeyVault(SecretUri=${secret_uri})"
  }

  production_app_settings = merge(
    local.platform_app_settings,
    var.app_settings,
    local.key_vault_app_settings,
    var.secret_app_settings
  )

  staging_app_settings = merge(
    local.production_app_settings,
    var.rollout.slot_app_settings_override
  )

  sticky_app_setting_names = distinct(concat(
    var.rollout.sticky_app_setting_names,
    keys(var.rollout.slot_app_settings_override)
  ))

  has_sticky_settings     = length(local.sticky_app_setting_names) > 0 || length(var.rollout.sticky_connection_string_names) > 0
  connection_string_names = nonsensitive(keys(var.connection_strings))

  # ---------------------------------------------------------------------------
  # Ingress / IP Restriction Rules
  # ---------------------------------------------------------------------------
  has_custom_ingress_rules = (
    var.networking.front_door_id != null ||
    length(var.networking.allowed_cidrs) > 0 ||
    length(var.networking.allowed_subnet_ids) > 0
  )

  ip_restriction_default_action = coalesce(
    var.networking.ip_restriction_default_action,
    local.has_custom_ingress_rules ? "Deny" : "Allow"
  )

  front_door_ip_restrictions = var.networking.front_door_id != null ? [
    {
      name                      = "allow-front-door"
      priority                  = 100
      action                    = "Allow"
      ip_address                = null
      service_tag               = "AzureFrontDoor.Backend"
      virtual_network_subnet_id = null
      x_azure_fdid              = [var.networking.front_door_id]
    }
  ] : []

  cidr_ip_restrictions = [
    for idx, cidr in var.networking.allowed_cidrs : {
      name                      = "allow-cidr-${idx + 1}"
      priority                  = 200 + (idx * 10)
      action                    = "Allow"
      ip_address                = cidr
      service_tag               = null
      virtual_network_subnet_id = null
      x_azure_fdid              = null
    }
  ]

  subnet_ip_restrictions = [
    for idx, subnet_id in var.networking.allowed_subnet_ids : {
      name                      = "allow-subnet-${idx + 1}"
      priority                  = 500 + (idx * 10)
      action                    = "Allow"
      ip_address                = null
      service_tag               = null
      virtual_network_subnet_id = subnet_id
      x_azure_fdid              = null
    }
  ]

  ip_restrictions = concat(
    local.front_door_ip_restrictions,
    local.cidr_ip_restrictions,
    local.subnet_ip_restrictions
  )

  scm_ip_restrictions = [
    for idx, cidr in var.networking.scm_allowed_cidrs : {
      name       = "allow-scm-cidr-${idx + 1}"
      priority   = 200 + (idx * 10)
      action     = "Allow"
      ip_address = cidr
    }
  ]
}
