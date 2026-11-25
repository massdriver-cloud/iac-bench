# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  count    = var.resource_group_name == null ? 1 : 0
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

locals {
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : azurerm_resource_group.rg[0].name
  location            = var.location

  staging_image = var.staging_container_image != null ? var.staging_container_image : var.container_image

  common_app_settings = merge(
    {
      "WEBSITES_PORT" = tostring(var.container_port)
    },
    var.enable_observability && length(azurerm_application_insights.app) > 0 ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.app[0].connection_string
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.app[0].instrumentation_key
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    } : {},
    var.app_settings
  )

  staging_app_settings = merge(
    local.common_app_settings,
    var.staging_app_settings
  )
}

# 2. Service Plan
resource "azurerm_service_plan" "plan" {
  count                  = var.custom_service_plan_id == null ? 1 : 0
  name                   = "asp-${var.name}"
  resource_group_name    = local.resource_group_name
  location               = local.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

locals {
  service_plan_id = var.custom_service_plan_id != null ? var.custom_service_plan_id : azurerm_service_plan.plan[0].id
}

# 3. Linux Web App (Main Service)
resource "azurerm_linux_web_app" "app" {
  name                      = "app-${var.name}"
  resource_group_name       = local.resource_group_name
  location                  = local.location
  service_plan_id           = local.service_plan_id
  https_only                = var.https_only
  virtual_network_subnet_id = var.vnet_subnet_id

  identity {
    type         = var.identity_type
    identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : null
  }

  site_config {
    always_on                               = var.always_on
    ftps_state                              = var.ftps_state
    minimum_tls_version                     = var.minimum_tls_version
    http2_enabled                           = var.http2_enabled
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_minutes
    vnet_route_all_enabled                  = var.vnet_subnet_id != null ? var.vnet_route_all_enabled : false
    container_registry_use_managed_identity = var.container_registry_use_managed_identity
    app_command_line                        = var.app_command_line

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        action                    = coalesce(ip_restriction.value.action, "Allow")
        priority                  = coalesce(ip_restriction.value.priority, 100)
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restrictions
      content {
        name                      = scm_ip_restriction.value.name
        ip_address                = scm_ip_restriction.value.ip_address
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
        action                    = coalesce(scm_ip_restriction.value.action, "Allow")
        priority                  = coalesce(scm_ip_restriction.value.priority, 100)
      }
    }
  }

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  app_settings = local.common_app_settings
  tags         = var.tags
}

# 4. Deployment Slot (Staging for Blue/Green Rollouts)
resource "azurerm_linux_web_app_slot" "staging" {
  count                     = var.enable_staging_slot ? 1 : 0
  name                      = "staging"
  app_service_id            = azurerm_linux_web_app.app.id
  https_only                = var.https_only
  virtual_network_subnet_id = var.vnet_subnet_id

  identity {
    type         = var.identity_type
    identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : null
  }

  site_config {
    always_on                               = var.always_on
    ftps_state                              = var.ftps_state
    minimum_tls_version                     = var.minimum_tls_version
    http2_enabled                           = var.http2_enabled
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_minutes
    vnet_route_all_enabled                  = var.vnet_subnet_id != null ? var.vnet_route_all_enabled : false
    container_registry_use_managed_identity = var.container_registry_use_managed_identity
    app_command_line                        = var.app_command_line

    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        action                    = coalesce(ip_restriction.value.action, "Allow")
        priority                  = coalesce(ip_restriction.value.priority, 100)
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restrictions
      content {
        name                      = scm_ip_restriction.value.name
        ip_address                = scm_ip_restriction.value.ip_address
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
        action                    = coalesce(scm_ip_restriction.value.action, "Allow")
        priority                  = coalesce(scm_ip_restriction.value.priority, 100)
      }
    }
  }

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  app_settings = local.staging_app_settings
  tags         = var.tags
}

# 5. Autoscale Settings
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  count               = var.enable_autoscaling && var.custom_service_plan_id == null ? 1 : 0
  name                = "autoscale-${var.name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.plan[0].id

  profile {
    name = "defaultProfile"

    capacity {
      default = var.worker_count
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    # CPU Scale Out Rule
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
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

    # CPU Scale In Rule
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
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

    # Memory Scale Out Rule
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
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

    # Memory Scale In Rule
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
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

  tags = var.tags
}
