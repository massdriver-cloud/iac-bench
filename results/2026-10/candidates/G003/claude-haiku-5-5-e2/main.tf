locals {
  name_suffix = "${var.app_name}-${var.environment}"

  common_tags = merge(var.tags, {
    service     = var.app_name
    environment = var.environment
    managed_by  = "opentofu"
  })

  # Plan-level capability flags derived from SKU tier.
  sku_is_basic        = startswith(var.sku_name, "B")
  sku_is_premium_v    = can(regex("^(P[0-3]v[234]|P[1-3]mv3|I[1-3]v2)$", var.sku_name))
  autoscale_supported = !local.sku_is_basic
  slots_supported     = !local.sku_is_basic

  base_app_settings = merge(
    {
      WEBSITES_PORT                         = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
      DOCKER_ENABLE_CI                      = "false"
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    },
    var.app_settings,
  )
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.common_tags
}

resource "azurerm_service_plan" "this" {
  name                = "asp-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  os_type             = "Linux"
  sku_name            = var.sku_name

  # Autoscale owns the instance count when enabled; otherwise the fixed count applies.
  worker_count = var.autoscale == null ? var.instance_count : var.autoscale.min_instances

  zone_balancing_enabled = var.zone_redundant
  tags                   = local.common_tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || (local.sku_is_premium_v && var.instance_count >= 2)
      error_message = "zone_redundant requires a P*v2/v3 or I*v2 SKU and instance_count >= 2. Set zone_redundant = false or change sku_name/instance_count."
    }

    precondition {
      condition     = var.autoscale == null || local.autoscale_supported
      error_message = "autoscale is not supported on Basic (B*) SKUs. Use S*, P*v3 or I*v2."
    }

    precondition {
      condition     = !var.deployment_slot_enabled || local.slots_supported
      error_message = "deployment_slot_enabled requires a Standard tier or above. Basic (B*) SKUs do not support slots."
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale == null ? 0 : 1

  name                = "autoscale-${local.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.common_tags

  profile {
    name = "cpu-based"

    capacity {
      default = var.instance_count
      minimum = var.autoscale.min_instances
      maximum = var.autoscale.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale.scale_out_cpu_pct
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
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale.scale_in_cpu_pct
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                     = "app-${local.name_suffix}"
  location                                 = azurerm_resource_group.this.location
  resource_group_name                      = azurerm_resource_group.this.name
  service_plan_id                          = azurerm_service_plan.this.id
  https_only                               = true
  client_affinity_enabled                  = false
  ftp_publish_basic_authentication_enabled = false
  tags                                     = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.base_app_settings

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.deployment_slot_enabled ? 1 : 0

  name                                     = "staging"
  app_service_id                           = azurerm_linux_web_app.this.id
  https_only                               = true
  client_affinity_enabled                  = false
  ftp_publish_basic_authentication_enabled = false
  tags                                     = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.base_app_settings

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "diag-${local.name_suffix}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  name                       = "diag-plan-${local.name_suffix}"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }
}
