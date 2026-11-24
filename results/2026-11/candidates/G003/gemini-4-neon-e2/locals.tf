resource "random_string" "suffix" {
  count   = var.name_suffix == null ? 1 : 0
  length  = 4
  upper   = false
  special = false
}

locals {
  suffix    = coalesce(var.name_suffix, try(random_string.suffix[0].result, ""))
  base_name = "${var.service_name}-${var.environment}"

  # Standardized Azure resource names
  resource_group_name = coalesce(var.resource_group_name, "rg-${local.base_name}-${local.suffix}")
  service_plan_name   = "asp-${local.base_name}-${local.suffix}"
  web_app_name        = "app-${local.base_name}-${local.suffix}"
  log_analytics_name  = "law-${local.base_name}-${local.suffix}"
  app_insights_name   = "appi-${local.base_name}-${local.suffix}"
  autoscale_name      = "autoscale-${local.base_name}-${local.suffix}"
  action_group_name   = "ag-${local.base_name}-${local.suffix}"
  web_test_name       = "avail-${local.base_name}-${local.suffix}"
  private_ep_name     = "pe-${local.base_name}-${local.suffix}"

  # Azure Monitor Action Group short_name is limited to 12 alphanumeric characters.
  action_group_short_name = substr(replace("${var.service_name}${var.environment}", "/[^a-zA-Z0-9]/", ""), 0, 12)

  # Standardized governance tags merged with caller tags
  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )

  # ----------------------------------------------------------------------------
  # Capacity & SKU Resolution
  # ----------------------------------------------------------------------------
  size_to_sku = {
    dev    = "S1"
    small  = "P0v3"
    medium = "P1v3"
    large  = "P2v3"
    xlarge = "P3v3"
  }

  create_service_plan = var.existing_service_plan_id == null
  sku_name            = coalesce(var.capacity.sku_name, local.size_to_sku[var.capacity.size])
  sku_upper           = upper(local.sku_name)

  is_free_or_shared         = contains(["F1", "D1", "FREE", "SHARED"], local.sku_upper)
  is_basic                  = startswith(local.sku_upper, "B")
  supports_always_on        = !local.is_free_or_shared
  supports_slots            = !local.is_free_or_shared && !local.is_basic
  supports_autoscale        = !local.is_free_or_shared && !local.is_basic
  supports_zone_redundancy  = can(regex("^P[0-9]+M?V[23]$|^I[0-9]+M?V2$", local.sku_upper))
  supports_private_endpoint = can(regex("^P[0-9]+M?V[23]$|^I[0-9]+M?V[12]$", local.sku_upper))

  # Zone redundancy on Azure App Service requires at least 3 workers spread across 3 AZs.
  effective_min_instances = var.availability.zone_redundant ? max(var.capacity.min_instances, 3) : var.capacity.min_instances
  effective_max_instances = max(var.capacity.max_instances, local.effective_min_instances)
  requested_default       = coalesce(var.capacity.default_instances, local.effective_min_instances)
  effective_default_instances = min(
    max(local.requested_default, local.effective_min_instances),
    local.effective_max_instances
  )

  # ----------------------------------------------------------------------------
  # Container Image & Registry Parsing (Production & Staging)
  # ----------------------------------------------------------------------------
  explicit_registry_url = var.container.registry_url != null ? trimsuffix(var.container.registry_url, "/") : null

  prod_image_parts       = split("/", var.container_image)
  prod_has_registry_host = length(local.prod_image_parts) > 1 && (strcontains(local.prod_image_parts[0], ".") || strcontains(local.prod_image_parts[0], ":") || local.prod_image_parts[0] == "localhost")
  prod_registry_url      = coalesce(local.explicit_registry_url, local.prod_has_registry_host ? "https://${local.prod_image_parts[0]}" : "https://index.docker.io")
  prod_registry_host     = replace(replace(local.prod_registry_url, "https://", ""), "http://", "")
  prod_docker_image_name = local.prod_has_registry_host && local.prod_image_parts[0] == local.prod_registry_host ? join("/", slice(local.prod_image_parts, 1, length(local.prod_image_parts))) : var.container_image

  staging_image_raw         = coalesce(var.rollout.staging_container_image, var.container_image)
  staging_image_parts       = split("/", local.staging_image_raw)
  staging_has_registry_host = length(local.staging_image_parts) > 1 && (strcontains(local.staging_image_parts[0], ".") || strcontains(local.staging_image_parts[0], ":") || local.staging_image_parts[0] == "localhost")
  staging_registry_url      = coalesce(local.explicit_registry_url, local.staging_has_registry_host ? "https://${local.staging_image_parts[0]}" : "https://index.docker.io")
  staging_registry_host     = replace(replace(local.staging_registry_url, "https://", ""), "http://", "")
  staging_docker_image_name = local.staging_has_registry_host && local.staging_image_parts[0] == local.staging_registry_host ? join("/", slice(local.staging_image_parts, 1, length(local.staging_image_parts))) : local.staging_image_raw

  use_acr_managed_identity = var.container.use_managed_identity_for_acr || var.container.acr_id != null

  # ----------------------------------------------------------------------------
  # Identity, Rollouts & Feature Toggles
  # ----------------------------------------------------------------------------
  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  effective_always_on = local.create_service_plan ? (var.availability.always_on && local.supports_always_on) : var.availability.always_on
  use_32_bit_worker   = local.create_service_plan ? local.is_free_or_shared : false

  warmup_ping_path = var.rollout.warmup_ping_path != null ? var.rollout.warmup_ping_path : var.health.path

  # ----------------------------------------------------------------------------
  # Observability Toggles & Alert Routing
  # ----------------------------------------------------------------------------
  create_log_analytics = var.observability.log_analytics_workspace_id == null
  log_analytics_id     = local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.observability.log_analytics_workspace_id

  create_action_group = length(var.observability.alert_emails) > 0 || var.observability.alert_webhook_url != null
  action_group_ids = distinct(concat(
    var.observability.alert_action_group_ids,
    local.create_action_group ? [azurerm_monitor_action_group.this[0].id] : []
  ))

  create_availability_test = (
    var.observability.app_insights_enabled &&
    var.observability.availability_test_enabled &&
    var.networking.public_network_access_enabled &&
    var.health.path != null
  )

  # ----------------------------------------------------------------------------
  # Composed App Settings (Platform Defaults -> Telemetry -> User -> Secrets)
  # ----------------------------------------------------------------------------
  platform_app_settings = merge(
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE           = tostring(var.container.enable_app_service_storage)
      WEBSITES_CONTAINER_START_TIME_LIMIT           = tostring(var.health.startup_timeout_seconds)
      WEBSITE_HEALTHCHECK_MAXPINGFAILURES           = tostring(var.health.max_ping_failures)
      WEBSITE_HEALTHCHECK_MAXUNHEALTHYWORKERPERCENT = tostring(var.health.max_unhealthy_worker_percent)
    },
    var.container.port != null ? {
      WEBSITES_PORT = tostring(var.container.port)
    } : {},
    var.rollout.staging_slot_enabled && local.warmup_ping_path != null ? {
      WEBSITE_SWAP_WARMUP_PING_PATH     = local.warmup_ping_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES = var.rollout.warmup_ping_statuses
    } : {},
    var.observability.app_insights_enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[0].connection_string
    } : {}
  )

  prod_app_settings = merge(
    local.platform_app_settings,
    var.app_settings,
    var.secret_app_settings,
    {
      APP_SLOT = "production"
    }
  )

  staging_app_settings = merge(
    local.platform_app_settings,
    var.app_settings,
    var.secret_app_settings,
    var.rollout.staging_app_settings,
    {
      APP_SLOT = var.rollout.staging_slot_name
    }
  )

  sticky_app_setting_names = distinct(concat(
    ["APP_SLOT"],
    var.sticky_app_settings
  ))
}
