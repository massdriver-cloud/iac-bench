locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  location            = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location

  service_plan_id   = var.create_service_plan ? azurerm_service_plan.this[0].id : var.service_plan_id
  service_plan_name = var.service_plan_name != null ? var.service_plan_name : "asp-${var.name}"

  app_insights_name                = var.application_insights_name != null ? var.application_insights_name : "appi-${var.name}"
  app_insights_instrumentation_key = var.create_application_insights ? (length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].instrumentation_key : null) : var.application_insights_instrumentation_key
  app_insights_connection_string   = var.create_application_insights ? (length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].connection_string : null) : var.application_insights_connection_string

  app_insights_settings = local.app_insights_instrumentation_key != null ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = local.app_insights_instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = local.app_insights_connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
  } : {}
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  count                  = var.create_service_plan ? 1 : 0
  name                   = local.service_plan_name
  resource_group_name    = local.resource_group_name
  location               = local.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

resource "azurerm_application_insights" "this" {
  count               = var.create_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = local.location
  resource_group_name = local.resource_group_name
  application_type    = "web"
  workspace_id        = var.log_analytics_workspace_id
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = local.location
  service_plan_id     = local.service_plan_id

  https_only                = var.https_only
  virtual_network_subnet_id = var.vnet_subnet_id
  tags                      = var.tags

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type         = var.identity_type
      identity_ids = (var.identity_type == "UserAssigned" || var.identity_type == "SystemAssigned, UserAssigned") ? var.identity_ids : null
    }
  }

  site_config {
    always_on                                     = var.always_on
    http2_enabled                                 = var.http2_enabled
    minimum_tls_version                           = var.min_tls_version
    ftps_state                                    = var.ftps_state
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_minutes
    vnet_route_all_enabled                        = var.vnet_subnet_id != null ? true : var.vnet_route_all_enabled
    container_registry_use_managed_identity       = var.container_registry_use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry_managed_identity_client_id

    application_stack {
      docker_image_name        = var.container_image_name
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        ip_address                = lookup(ip_restriction.value, "ip_address", null)
        service_tag               = lookup(ip_restriction.value, "service_tag", null)
        virtual_network_subnet_id = lookup(ip_restriction.value, "virtual_network_subnet_id", null)
        action                    = lookup(ip_restriction.value, "action", "Allow")
        priority                  = lookup(ip_restriction.value, "priority", 100)
        name                      = lookup(ip_restriction.value, "name", null)
        description               = lookup(ip_restriction.value, "description", null)
      }
    }
  }

  app_settings = merge(
    local.app_insights_settings,
    var.app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  https_only                = var.https_only
  virtual_network_subnet_id = var.vnet_subnet_id
  tags                      = var.tags

  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type         = var.identity_type
      identity_ids = (var.identity_type == "UserAssigned" || var.identity_type == "SystemAssigned, UserAssigned") ? var.identity_ids : null
    }
  }

  site_config {
    always_on                                     = var.always_on
    http2_enabled                                 = var.http2_enabled
    minimum_tls_version                           = var.min_tls_version
    ftps_state                                    = var.ftps_state
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_minutes
    vnet_route_all_enabled                        = var.vnet_subnet_id != null ? true : var.vnet_route_all_enabled
    container_registry_use_managed_identity       = var.container_registry_use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry_managed_identity_client_id

    application_stack {
      docker_image_name        = var.staging_container_image_name != null ? var.staging_container_image_name : var.container_image_name
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        ip_address                = lookup(ip_restriction.value, "ip_address", null)
        service_tag               = lookup(ip_restriction.value, "service_tag", null)
        virtual_network_subnet_id = lookup(ip_restriction.value, "virtual_network_subnet_id", null)
        action                    = lookup(ip_restriction.value, "action", "Allow")
        priority                  = lookup(ip_restriction.value, "priority", 100)
        name                      = lookup(ip_restriction.value, "name", null)
        description               = lookup(ip_restriction.value, "description", null)
      }
    }
  }

  app_settings = merge(
    local.app_insights_settings,
    var.app_settings,
    var.staging_app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = (var.create_service_plan && var.enable_autoscaling) ? 1 : 0
  name                = "autoscale-${var.name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = local.service_plan_id
  tags                = var.tags

  profile {
    name = "defaultProfile"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    # Scale Out - CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.cpu_scale_out_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale In - CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.cpu_scale_in_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale Out - Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.memory_scale_out_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale In - Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.memory_scale_in_threshold
        metric_namespace   = "microsoft.web/serverfarms"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}
