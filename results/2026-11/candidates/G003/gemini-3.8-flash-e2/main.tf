locals {
  default_tags = {
    ManagedBy   = "OpenTofu"
    Application = var.app_name
  }
  tags = merge(local.default_tags, var.tags)

  # SRE production defaults for containerized HTTP APIs
  default_app_settings = merge(
    {
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
      "WEBSITES_CONTAINER_START_TIME_LIMIT" = "300"
      "DOCKER_ENABLE_CI"                    = "false"
      "WEBSITES_PORT"                       = tostring(var.container_port)
    },
    var.application_insights_connection_string != null ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.application_insights_connection_string
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
      "XDT_MicrosoftApplicationInsights_Mode"      = "recommended"
    } : {}
  )

  app_settings = merge(local.default_app_settings, var.app_settings)

  # Service plan resolution
  service_plan_id = var.service_plan_id != null ? var.service_plan_id : azurerm_service_plan.this[0].id

  staging_image = coalesce(var.staging_container_image, var.container_image)
}

# -----------------------------------------------------------------------------
# Capacity: App Service Plan & Autoscale
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count                  = var.service_plan_id == null ? 1 : 0
  name                   = coalesce(var.service_plan_name, "asp-${var.app_name}")
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.autoscale_enabled && var.service_plan_id == null ? 1 : 0
  name                = "autoscale-asp-${var.app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = local.service_plan_id
  tags                = local.tags

  profile {
    name = "defaultAutoscaleProfile"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    # Scale out on CPU threshold
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

    # Scale in on CPU threshold
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

    # Scale out on Memory threshold
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = local.service_plan_id
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

    # Scale in on Memory threshold
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = local.service_plan_id
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
}

# -----------------------------------------------------------------------------
# Linux Web App (Production)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                          = var.app_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = local.service_plan_id
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  client_affinity_enabled       = var.client_affinity_enabled

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = var.always_on
    http2_enabled                     = var.http2_enabled
    minimum_tls_version               = var.min_tls_version
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path != null ? var.health_check_eviction_time_in_min : null
    vnet_route_all_enabled            = var.virtual_network_subnet_id != null ? var.vnet_route_all_enabled : false

    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        action                    = lookup(ip_restriction.value, "action", "Allow")
        ip_address                = lookup(ip_restriction.value, "ip_address", null)
        service_tag               = lookup(ip_restriction.value, "service_tag", null)
        virtual_network_subnet_id = lookup(ip_restriction.value, "virtual_network_subnet_id", null)
        name                      = lookup(ip_restriction.value, "name", null)
        priority                  = lookup(ip_restriction.value, "priority", 100)
        description               = lookup(ip_restriction.value, "description", null)
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restrictions
      content {
        action                    = lookup(scm_ip_restriction.value, "action", "Allow")
        ip_address                = lookup(scm_ip_restriction.value, "ip_address", null)
        service_tag               = lookup(scm_ip_restriction.value, "service_tag", null)
        virtual_network_subnet_id = lookup(scm_ip_restriction.value, "virtual_network_subnet_id", null)
        name                      = lookup(scm_ip_restriction.value, "name", null)
        priority                  = lookup(scm_ip_restriction.value, "priority", 100)
        description               = lookup(scm_ip_restriction.value, "description", null)
      }
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

    application_logs {
      file_system_level = "Information"
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  app_settings = local.app_settings

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Rollouts: Staging Deployment Slot
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count                         = var.staging_slot_enabled ? 1 : 0
  name                          = var.staging_slot_name
  app_service_id                = azurerm_linux_web_app.this.id
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  client_affinity_enabled       = var.client_affinity_enabled

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = var.always_on
    http2_enabled                     = var.http2_enabled
    minimum_tls_version               = var.min_tls_version
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path != null ? var.health_check_eviction_time_in_min : null
    vnet_route_all_enabled            = var.virtual_network_subnet_id != null ? var.vnet_route_all_enabled : false
    auto_swap_slot_name               = var.auto_swap_slot_name

    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        action                    = lookup(ip_restriction.value, "action", "Allow")
        ip_address                = lookup(ip_restriction.value, "ip_address", null)
        service_tag               = lookup(ip_restriction.value, "service_tag", null)
        virtual_network_subnet_id = lookup(ip_restriction.value, "virtual_network_subnet_id", null)
        name                      = lookup(ip_restriction.value, "name", null)
        priority                  = lookup(ip_restriction.value, "priority", 100)
        description               = lookup(ip_restriction.value, "description", null)
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restrictions
      content {
        action                    = lookup(scm_ip_restriction.value, "action", "Allow")
        ip_address                = lookup(scm_ip_restriction.value, "ip_address", null)
        service_tag               = lookup(scm_ip_restriction.value, "service_tag", null)
        virtual_network_subnet_id = lookup(scm_ip_restriction.value, "virtual_network_subnet_id", null)
        name                      = lookup(scm_ip_restriction.value, "name", null)
        priority                  = lookup(scm_ip_restriction.value, "priority", 100)
        description               = lookup(scm_ip_restriction.value, "description", null)
      }
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

    application_logs {
      file_system_level = "Information"
    }
  }

  app_settings = merge(local.app_settings, var.staging_app_settings)

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ACR Role Assignments (Managed Identity Authentication)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_id != null && var.container_registry_use_managed_identity ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_slot" {
  count                = var.acr_id != null && var.container_registry_use_managed_identity && var.staging_slot_enabled ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
