resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

locals {
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location
  default_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "OpenTofu"
    },
    var.tags
  )
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-asp"
  resource_group_name    = local.resource_group_name
  location               = local.resource_group_location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled

  tags = local.default_tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.enable_autoscale ? 1 : 0
  name                = "${var.name}-autoscale"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "AutoCreatedScaleCondition"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
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
        metric_resource_id = azurerm_service_plan.this.id
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

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_memory_scale_out_threshold
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
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_memory_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = local.default_tags
}

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.create_log_analytics_workspace ? 1 : 0
  name                = "${var.name}-law"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_in_days

  tags = local.default_tags
}

locals {
  has_log_analytics          = var.create_log_analytics_workspace || var.log_analytics_workspace_id != null
  log_analytics_workspace_id = var.create_log_analytics_workspace ? (length(azurerm_log_analytics_workspace.this) > 0 ? azurerm_log_analytics_workspace.this[0].id : null) : var.log_analytics_workspace_id
}

resource "azurerm_application_insights" "this" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "${var.name}-appinsights"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"

  tags = local.default_tags
}

resource "azurerm_linux_web_app" "this" {
  name                      = var.name
  resource_group_name       = local.resource_group_name
  location                  = local.resource_group_location
  service_plan_id           = azurerm_service_plan.this.id
  https_only                = true
  virtual_network_subnet_id = var.vnet_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = var.always_on
    http2_enabled                           = var.enable_http2
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_path != null ? var.health_check_eviction_time_in_minutes : null
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = var.cors_support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        action                    = ip_restriction.value.action
        priority                  = ip_restriction.value.priority
        description               = ip_restriction.value.description
      }
    }
  }

  app_settings = merge(
    {
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
      "WEBSITES_PORT"                       = tostring(var.container_port)
      "PORT"                                = tostring(var.container_port)
    },
    var.enable_application_insights && length(azurerm_application_insights.this) > 0 ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this[0].connection_string
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.this[0].instrumentation_key
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    } : {},
    var.app_settings
  )

  tags = local.default_tags
}

resource "azurerm_linux_web_app_slot" "this" {
  count                     = var.enable_staging_slot ? 1 : 0
  name                      = var.staging_slot_name
  app_service_id            = azurerm_linux_web_app.this.id
  virtual_network_subnet_id = var.vnet_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = var.always_on
    http2_enabled                           = var.enable_http2
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_path != null ? var.health_check_eviction_time_in_minutes : null
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = var.cors_support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        action                    = ip_restriction.value.action
        priority                  = ip_restriction.value.priority
        description               = ip_restriction.value.description
      }
    }
  }

  app_settings = merge(
    {
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
      "WEBSITES_PORT"                       = tostring(var.container_port)
      "PORT"                                = tostring(var.container_port)
    },
    var.enable_application_insights && length(azurerm_application_insights.this) > 0 ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this[0].connection_string
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.this[0].instrumentation_key
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    } : {},
    var.app_settings,
    var.slot_app_settings
  )

  tags = local.default_tags
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count                      = var.enable_diagnostic_settings && local.has_log_analytics ? 1 : 0
  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "web_app_slot" {
  count                      = var.enable_diagnostic_settings && var.enable_staging_slot && local.has_log_analytics ? 1 : 0
  name                       = "${var.name}-slot-diag"
  target_resource_id         = azurerm_linux_web_app_slot.this[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  count                      = var.enable_diagnostic_settings && local.has_log_analytics ? 1 : 0
  name                       = "${var.name}-asp-diag"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  metric {
    category = "AllMetrics"
  }
}
