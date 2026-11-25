# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  location            = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location
  service_plan_id     = var.create_service_plan ? azurerm_service_plan.this[0].id : var.service_plan_id

  appinsights_settings = var.enable_application_insights ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.this[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this[0].connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    "XDT_MicrosoftApplicationInsights_Mode"      = "recommended"
  } : {}

  merged_app_settings = merge(
    local.appinsights_settings,
    var.app_settings
  )
}

# -----------------------------------------------------------------------------
# Resource Group (Optional Creation)
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Capacity: App Service Plan & Autoscale
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count                  = var.create_service_plan ? 1 : 0
  name                   = "${var.name}-asp"
  resource_group_name    = local.resource_group_name
  location               = local.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.create_service_plan && var.enable_autoscale ? 1 : 0
  name                = "${var.name}-autoscale"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = local.service_plan_id

  profile {
    name = "defaultProfile"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_threshold
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
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Observability: Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_application_insights" "this" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "${var.name}-appinsights"
  location            = local.location
  resource_group_name = local.resource_group_name
  application_type    = "web"
  workspace_id        = var.log_analytics_workspace_id
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Primary Service: Linux Web App (Containerized HTTP API)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                      = var.name
  resource_group_name       = local.resource_group_name
  location                  = local.location
  service_plan_id           = local.service_plan_id
  https_only                = var.https_only
  client_affinity_enabled   = var.client_affinity_enabled
  virtual_network_subnet_id = var.vnet_subnet_id

  identity {
    type         = var.identity_type
    identity_ids = var.identity_ids
  }

  site_config {
    always_on                               = var.always_on
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_minutes
    minimum_tls_version                     = var.minimum_tls_version
    http2_enabled                           = var.http2_enabled
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.docker_image_name
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    http_logs {
      file_system {
        retention_in_mb   = 35
        retention_in_days = 7
      }
    }
    application_logs {
      file_system_level = "Information"
    }
  }

  app_settings = local.merged_app_settings
  tags         = var.tags
}

# -----------------------------------------------------------------------------
# Rollouts: Staging Deployment Slot
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  identity {
    type         = var.identity_type
    identity_ids = var.identity_ids
  }

  site_config {
    always_on                               = var.always_on
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_minutes
    minimum_tls_version                     = var.minimum_tls_version
    http2_enabled                           = var.http2_enabled
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.docker_image_name
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
  }

  app_settings = merge(local.merged_app_settings, { "SLOT_NAME" = var.staging_slot_name })
  tags         = merge(var.tags, { Slot = var.staging_slot_name })
}

# -----------------------------------------------------------------------------
# Observability: Diagnostic Settings
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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
    category = "AppServiceAuditLogs"
  }
  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }
  enabled_log {
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
