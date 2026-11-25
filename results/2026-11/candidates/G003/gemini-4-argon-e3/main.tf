resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name_prefix = "${var.service_name}-${var.environment}"
  unique_name = "${local.name_prefix}-${random_string.suffix.result}"

  resource_group_name = coalesce(var.resource_group_name, "rg-${local.name_prefix}")

  is_standard_or_higher = (
    startswith(var.capacity.sku_name, "S") ||
    startswith(var.capacity.sku_name, "P")
  )

  zone_balancing_enabled = var.availability.zone_balancing_enabled

  # Staging slots are supported on Standard and Premium tiers
  enable_staging_slot = var.rollout.enable_staging_slot && local.is_standard_or_higher

  identity_type = (
    var.identity.enable_system_assigned && length(var.identity.user_assigned_ids) > 0 ? "SystemAssigned, UserAssigned" :
    var.identity.enable_system_assigned ? "SystemAssigned" :
    length(var.identity.user_assigned_ids) > 0 ? "UserAssigned" :
    null
  )

  # Standard container runtime and warm-up app settings
  base_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container.port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DOCKER_ENABLE_CI                    = "false"
    },
    var.health.warm_up_path != null ? {
      WEBSITE_WARMUP_PATH     = var.health.warm_up_path
      WEBSITE_WARMUP_STATUSES = var.health.warm_up_status_codes
    } : {},
    var.observability.enable_application_insights ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
      APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.this[0].instrumentation_key
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    } : {}
  )

  merged_app_settings = merge(local.base_app_settings, var.app_settings)

  sticky_app_setting_names = distinct(concat(
    var.sticky_app_settings.app_setting_names,
    ["DEPLOYMENT_SLOT"]
  ))

  common_tags = merge(
    {
      "service"     = var.service_name
      "environment" = var.environment
      "managed_by"  = "opentofu"
    },
    var.tags
  )
}

resource "azurerm_resource_group" "this" {
  count    = var.resource_group_name == null ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# Observability: Log Analytics & Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.observability.log_analytics_workspace_id == null ? 1 : 0
  name                = "law-${local.unique_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.retention_in_days
  daily_quota_gb      = var.observability.daily_quota_gb
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

locals {
  log_analytics_workspace_id = coalesce(
    var.observability.log_analytics_workspace_id,
    try(azurerm_log_analytics_workspace.this[0].id, null)
  )
}

resource "azurerm_application_insights" "this" {
  count               = var.observability.enable_application_insights ? 1 : 0
  name                = "appi-${local.unique_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

# -----------------------------------------------------------------------------
# Compute & Capacity: Service Plan and Autoscale
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "asp-${local.unique_name}"
  location               = var.location
  resource_group_name    = local.resource_group_name
  os_type                = "Linux"
  sku_name               = var.capacity.sku_name
  worker_count           = var.capacity.default_instances
  zone_balancing_enabled = local.zone_balancing_enabled
  tags                   = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.capacity.enable_autoscale && var.capacity.max_instances > var.capacity.min_instances ? 1 : 0
  name                = "autoscale-${local.unique_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default-capacity-profile"

    capacity {
      default = var.capacity.default_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    # CPU Scale Out
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.cpu_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # CPU Scale In
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.cpu_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    # Memory Scale Out
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.memory_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Web Application (Production Slot)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                                           = "app-${local.unique_name}"
  location                                       = var.location
  resource_group_name                            = local.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  virtual_network_subnet_id                      = var.networking.integration_subnet_id
  tags                                           = local.common_tags

  app_settings = merge(
    local.merged_app_settings,
    {
      DEPLOYMENT_SLOT = "production"
    }
  )

  sticky_settings {
    app_setting_names       = local.sticky_app_setting_names
    connection_string_names = length(var.sticky_app_settings.connection_string_names) > 0 ? var.sticky_app_settings.connection_string_names : null
  }

  dynamic "identity" {
    for_each = local.identity_type != null ? [1] : []
    content {
      type         = local.identity_type
      identity_ids = length(var.identity.user_assigned_ids) > 0 ? var.identity.user_assigned_ids : null
    }
  }

  site_config {
    always_on                               = var.availability.always_on
    http2_enabled                           = var.availability.http2_enabled
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    use_32_bit_worker                       = false
    vnet_route_all_enabled                  = var.networking.integration_subnet_id != null ? var.networking.vnet_route_all_enabled : false
    health_check_path                       = var.health.path
    health_check_eviction_time_in_min       = var.health.eviction_time_in_min
    container_registry_use_managed_identity = var.container.use_managed_identity_for_acr
    app_command_line                        = var.container.startup_command
    scm_use_main_ip_restriction             = var.networking.scm_use_main_ip_restriction

    application_stack {
      docker_image_name        = var.container.image_name
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "cors" {
      for_each = length(var.networking.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.networking.cors_allowed_origins
        support_credentials = var.networking.cors_support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = var.networking.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        service_tag               = ip_restriction.value.service_tag
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = var.observability.http_logs_retention_mb
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Rollouts: Staging Slot for Blue/Green & Safe Swaps
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = local.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  virtual_network_subnet_id                      = var.networking.integration_subnet_id
  tags                                           = local.common_tags

  app_settings = merge(
    local.merged_app_settings,
    {
      DEPLOYMENT_SLOT = "staging"
    }
  )

  dynamic "identity" {
    for_each = local.identity_type != null ? [1] : []
    content {
      type         = local.identity_type
      identity_ids = length(var.identity.user_assigned_ids) > 0 ? var.identity.user_assigned_ids : null
    }
  }

  site_config {
    always_on                               = var.availability.always_on
    http2_enabled                           = var.availability.http2_enabled
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    use_32_bit_worker                       = false
    vnet_route_all_enabled                  = var.networking.integration_subnet_id != null ? var.networking.vnet_route_all_enabled : false
    health_check_path                       = var.health.path
    health_check_eviction_time_in_min       = var.health.eviction_time_in_min
    container_registry_use_managed_identity = var.container.use_managed_identity_for_acr
    app_command_line                        = var.container.startup_command
    scm_use_main_ip_restriction             = var.networking.scm_use_main_ip_restriction
    auto_swap_slot_name                     = var.rollout.auto_swap_enabled ? "production" : null

    application_stack {
      docker_image_name        = coalesce(var.rollout.staging_image_name, var.container.image_name)
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "cors" {
      for_each = length(var.networking.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.networking.cors_allowed_origins
        support_credentials = var.networking.cors_support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = var.networking.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        service_tag               = ip_restriction.value.service_tag
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = var.observability.http_logs_retention_mb
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Observability: Diagnostic Settings & Golden Signal Metric Alerts
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-app-${local.unique_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "diag-plan-${local.unique_name}"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.observability.enable_default_alerts ? 1 : 0
  name                = "alert-${local.unique_name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when HTTP 5xx server errors exceed threshold for ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.http_5xx_threshold
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.observability.enable_default_alerts ? 1 : 0
  name                = "alert-${local.unique_name}-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when average HTTP response time exceeds threshold for ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.response_time_threshold_sec
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.observability.enable_default_alerts ? 1 : 0
  name                = "alert-${local.unique_name}-health"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when App Service health check status drops below threshold for ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.health_check_min_percent
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
