resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  name_prefix = "${var.name}-${var.environment}"
  unique_name = "${local.name_prefix}-${random_string.suffix.result}"

  resource_group_name = coalesce(
    var.resource_group_name,
    try(azurerm_resource_group.this[0].name, null)
  )

  default_tags = {
    service     = var.name
    environment = var.environment
    managed_by  = "opentofu"
  }
  tags = merge(local.default_tags, var.tags)

  create_log_analytics = var.observability.log_analytics_workspace_id == null
  log_analytics_workspace_id = coalesce(
    var.observability.log_analytics_workspace_id,
    try(azurerm_log_analytics_workspace.this[0].id, null)
  )

  create_app_insights = var.observability.application_insights_id == null
  app_insights_connection_string = coalesce(
    var.observability.application_insights_connection_string,
    try(azurerm_application_insights.this[0].connection_string, null)
  )

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  standard_app_settings = merge(
    {
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"             = "false"
      "WEBSITES_PORT"                                   = tostring(var.container.port)
      "DOCKER_ENABLE_CI"                                = "false"
      "WEBSITE_ADD_SITENAME_BINDINGS_IN_APPHOST_CONFIG" = "1"
      "WEBSITES_CONTAINER_START_TIME_LIMIT"             = tostring(var.health.container_start_time_limit)
    },
    length(var.rollout.warmup_init_paths) > 0 ? {
      "WEBSITE_SWAP_WARMUP_PING_PATH"     = var.rollout.warmup_init_paths[0]
      "WEBSITE_SWAP_WARMUP_PING_STATUSES" = join(",", var.rollout.warmup_status_codes)
      "WEBSITE_WARMUP_PATH"               = var.rollout.warmup_init_paths[0]
    } : {},
    local.create_app_insights ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this[0].connection_string
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.this[0].instrumentation_key
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
      } : (
      local.app_insights_connection_string != null ? {
        "APPLICATIONINSIGHTS_CONNECTION_STRING"      = local.app_insights_connection_string
        "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
      } : {}
    )
  )

  merged_app_settings = merge(local.standard_app_settings, var.app_settings)

  ip_restrictions = concat(
    [
      for idx, cidr in var.network.allowed_cidrs : {
        name                      = "allow-cidr-${idx}"
        priority                  = 100 + idx
        action                    = "Allow"
        ip_address                = cidr
        virtual_network_subnet_id = null
        service_tag               = null
      }
    ],
    [
      for idx, subnet_id in var.network.allowed_subnet_ids : {
        name                      = "allow-subnet-${idx}"
        priority                  = 200 + idx
        action                    = "Allow"
        ip_address                = null
        virtual_network_subnet_id = subnet_id
        service_tag               = null
      }
    ],
    [
      for idx, tag in var.network.allowed_service_tags : {
        name                      = "allow-tag-${idx}"
        priority                  = 300 + idx
        action                    = "Allow"
        ip_address                = null
        virtual_network_subnet_id = null
        service_tag               = tag
      }
    ]
  )
}

resource "azurerm_resource_group" "this" {
  count    = var.resource_group_name == null ? 1 : 0
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# ------------------------------------------------------------------------------
# Observability Foundation: Log Analytics & Application Insights
# ------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = local.create_log_analytics ? 1 : 0
  name                = "law-${local.unique_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.retention_in_days
  daily_quota_gb      = var.observability.daily_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  count               = local.create_app_insights ? 1 : 0
  name                = "appi-${local.unique_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.retention_in_days
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.tags
}

# ------------------------------------------------------------------------------
# Compute & Capacity: App Service Plan & Autoscale
# ------------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                         = "asp-${local.unique_name}"
  location                     = var.location
  resource_group_name          = local.resource_group_name
  os_type                      = "Linux"
  sku_name                     = var.capacity.sku_name
  zone_balancing_enabled       = var.capacity.zone_balancing_enabled
  worker_count                 = var.capacity.default_instances
  per_site_scaling_enabled     = false
  maximum_elastic_worker_count = null
  tags                         = local.tags

  lifecycle {
    ignore_changes = [
      worker_count
    ]
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.capacity.autoscale_enabled ? 1 : 0
  name                = "autoscale-${local.unique_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "default-sre-autoscale"

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
        threshold          = var.capacity.scale_out_cpu_threshold
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
        threshold          = var.capacity.scale_in_cpu_threshold
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
        threshold          = var.capacity.scale_out_memory_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # HTTP Queue Depth Scale Out
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.scale_out_http_queue_depth
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Linux Web App (Production Slot)
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                                           = "app-${local.unique_name}"
  location                                       = var.location
  resource_group_name                            = local.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = var.health.client_affinity_enabled
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.virtual_network_subnet_id
  vnet_image_pull_enabled                        = var.network.virtual_network_subnet_id != null ? var.network.vnet_image_pull_enabled : false
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = merge(local.merged_app_settings, { "DEPLOYMENT_SLOT" = "production" })
  tags                                           = local.tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = var.health.always_on
    http2_enabled                                 = var.health.http2_enabled
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    vnet_route_all_enabled                        = var.network.virtual_network_subnet_id != null ? var.network.vnet_route_all_enabled : false
    container_registry_use_managed_identity       = var.container.registry_use_msi
    container_registry_managed_identity_client_id = var.container.registry_msi_client_id
    app_command_line                              = var.container.startup_command
    ip_restriction_default_action                 = var.network.ip_restriction_default_action
    scm_ip_restriction_default_action             = var.network.scm_ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.network.scm_use_main_ip_restriction

    application_stack {
      docker_image_name        = "${var.container.image_name}:${var.container.image_tag}"
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        service_tag               = ip_restriction.value.service_tag
      }
    }

    dynamic "cors" {
      for_each = length(var.network.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.network.cors_allowed_origins
        support_credentials = var.network.cors_support_credentials
      }
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

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

  sticky_settings {
    app_setting_names = distinct(concat(
      ["DEPLOYMENT_SLOT"],
      var.rollout.slot_sticky_app_settings
    ))
  }
}

# ------------------------------------------------------------------------------
# Safe Rollout: Staging Slot
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.rollout.staging_slot_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = var.health.client_affinity_enabled
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.virtual_network_subnet_id
  vnet_image_pull_enabled                        = var.network.virtual_network_subnet_id != null ? var.network.vnet_image_pull_enabled : false
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = merge(local.merged_app_settings, { "DEPLOYMENT_SLOT" = "staging" })
  tags                                           = local.tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = var.health.always_on
    http2_enabled                                 = var.health.http2_enabled
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    vnet_route_all_enabled                        = var.network.virtual_network_subnet_id != null ? var.network.vnet_route_all_enabled : false
    container_registry_use_managed_identity       = var.container.registry_use_msi
    container_registry_managed_identity_client_id = var.container.registry_msi_client_id
    app_command_line                              = var.container.startup_command
    auto_swap_slot_name                           = var.rollout.auto_swap_enabled ? "production" : null
    ip_restriction_default_action                 = var.network.ip_restriction_default_action
    scm_ip_restriction_default_action             = var.network.scm_ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.network.scm_use_main_ip_restriction

    application_stack {
      docker_image_name        = "${var.container.image_name}:${coalesce(var.rollout.staging_image_tag, var.container.image_tag)}"
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        service_tag               = ip_restriction.value.service_tag
      }
    }

    dynamic "cors" {
      for_each = length(var.network.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.network.cors_allowed_origins
        support_credentials = var.network.cors_support_credentials
      }
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

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

# ------------------------------------------------------------------------------
# Diagnostic Logs & Metrics Shipping to Log Analytics
# ------------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${azurerm_linux_web_app.this.name}"
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

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = var.rollout.staging_slot_enabled ? 1 : 0
  name                       = "diag-${azurerm_linux_web_app.this.name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
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
  name                       = "diag-${azurerm_service_plan.this.name}"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# ------------------------------------------------------------------------------
# Golden Signals & Health Alerts (SRE Observability)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.unique_name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "High rate of HTTP 5xx server errors on ${azurerm_linux_web_app.this.name}."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_5xx_threshold
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.unique_name}-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Elevated HTTP response time on ${azurerm_linux_web_app.this.name}."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_latency_p95_ms_threshold / 1000
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.unique_name}-healthcheck"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Instance health check percentage degraded on ${azurerm_linux_web_app.this.name}."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.alert_health_threshold_percent
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.unique_name}-high-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Sustained high CPU utilization on App Service Plan ${azurerm_service_plan.this.name}."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_cpu_threshold_percent
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.unique_name}-high-memory"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Sustained high Memory utilization on App Service Plan ${azurerm_service_plan.this.name}."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_memory_threshold_percent
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
