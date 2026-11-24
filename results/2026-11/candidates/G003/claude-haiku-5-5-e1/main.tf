locals {
  # SKU capability flags, derived from the SKU so callers never set them.
  autoscale_capable = can(regex("^[SP]", var.sku_name))
  zone_capable      = can(regex("^P[0-9]+(v2|v3|mv3)$", var.sku_name))

  # Containers must not mount the App Service content share, so it is disabled
  # by default. Caller-supplied settings can override it.
  base_app_settings = merge(
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    },
    var.application_insights_connection_string == null ? {} : {
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
    },
    var.app_settings,
  )

  docker_image = "${var.container_image_name}:${var.container_image_tag}"

  diagnostic_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
  ]
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  # On scalable SKUs autoscale owns the instance count, so leave it unset to
  # avoid fighting the autoscale setting. On B-series the count is fixed.
  worker_count = local.autoscale_capable ? null : var.min_instances

  zone_balancing_enabled   = var.zone_redundant
  per_site_scaling_enabled = false

  tags = var.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || local.zone_capable
      error_message = "zone_redundant = true requires a P*v2, P*v3, or P*mv3 SKU; ${var.sku_name} does not support zone redundancy. Set zone_redundant = false or choose a premium SKU."
    }
    precondition {
      condition     = !var.zone_redundant || var.min_instances >= 2
      error_message = "zone_redundant = true requires min_instances >= 2 so every zone has capacity."
    }
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be greater than or equal to min_instances."
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  client_affinity_enabled       = false
  public_network_access_enabled = true

  # Deploys go through Entra ID credentials in CI, not basic-auth FTP/WebDeploy.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.base_app_settings

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    application_stack {
      docker_image_name        = local.docker_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Warning"
    }

    http_logs {
      file_system {
        retention_in_days = var.log_retention_days
        retention_in_mb   = 35
      }
    }
  }

  tags = var.tags
}

# Rollout target. Deploy the new image here, verify it, then swap into production.
resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true

  client_affinity_enabled       = false
  public_network_access_enabled = true

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.base_app_settings

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    application_stack {
      docker_image_name        = local.docker_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Warning"
    }

    http_logs {
      file_system {
        retention_in_days = var.log_retention_days
        retention_in_mb   = 35
      }
    }
  }

  tags = var.tags
}

# CPU-based autoscale. Created only for SKUs that support it (S and P tiers).
resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_capable ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "default"

    capacity {
      minimum = var.min_instances
      maximum = var.max_instances
      default = var.min_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = var.tags
}

# Observability: export logs and metrics to Log Analytics when a workspace is given.
resource "azurerm_monitor_diagnostic_setting" "app" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.log_analytics_workspace_id != null && var.enable_staging_slot ? 1 : 0

  name                       = "${var.name}-staging-diag"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "${var.name}-plan-diag"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}
