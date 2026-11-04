# One resource group per service: clean lifecycle, RBAC and cost boundaries.
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Capacity: a dedicated plan per service (no noisy neighbours between services).
# -----------------------------------------------------------------------------
resource "azurerm_service_plan" "main" {
  name                   = "asp-${var.name}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = local.capacity
  zone_balancing_enabled = var.zone_redundant

  tags = local.tags
}

# -----------------------------------------------------------------------------
# The web app (production slot)
# -----------------------------------------------------------------------------
resource "azurerm_linux_web_app" "main" {
  name                = "app-${var.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id

  # Opinionated baseline: TLS-only, no ARR affinity cookie (stateless HTTP APIs),
  # basic auth for ftp/webdeploy off (deploy via CI with managed identity/RBAC).
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.app_settings

  identity {
    type         = var.identity_type
    identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : null
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    websockets_enabled                            = var.websockets_enabled
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = local.health_check_eviction_time_in_min
    vnet_route_all_enabled                        = var.vnet_route_all_enabled
    container_registry_use_managed_identity       = var.container.use_managed_identity
    container_registry_managed_identity_client_id = var.container.identity_client_id

    application_stack {
      docker_image_name        = var.container.image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = var.auto_heal.enabled ? [var.auto_heal] : []
      content {
        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = "00:01:00"
        }
        trigger {
          dynamic "requests" {
            for_each = auto_heal_setting.value.request_count != null ? [1] : []
            content {
              count    = auto_heal_setting.value.request_count
              interval = auto_heal_setting.value.request_interval
            }
          }
          dynamic "slow_request" {
            for_each = auto_heal_setting.value.slow_request_count != null ? [1] : []
            content {
              count      = auto_heal_setting.value.slow_request_count
              interval   = auto_heal_setting.value.slow_request_interval
              time_taken = auto_heal_setting.value.slow_request_time
            }
          }
          status_code {
            count             = auto_heal_setting.value.status_code_count
            interval          = auto_heal_setting.value.status_code_interval
            status_code_range = auto_heal_setting.value.status_code_range
          }
        }
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
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
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  tags = local.tags
}

# Grant the app's system-assigned identity pull rights on ACR when asked.
resource "azurerm_role_assignment" "acr_pull" {
  count = var.container.registry_id != null && can(regex("SystemAssigned", var.identity_type)) ? 1 : 0

  scope                = var.container.registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# -----------------------------------------------------------------------------
# Rollouts: staging slot + explicit promotion
# -----------------------------------------------------------------------------
resource "azurerm_linux_web_app_slot" "staging" {
  count = local.slot_enabled ? 1 : 0

  name           = local.slot_name
  app_service_id = azurerm_linux_web_app.main.id

  https_only                                     = true
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.app_settings

  identity {
    type         = var.identity_type
    identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : null
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    websockets_enabled                            = var.websockets_enabled
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = local.health_check_eviction_time_in_min
    vnet_route_all_enabled                        = var.vnet_route_all_enabled
    container_registry_use_managed_identity       = var.container.use_managed_identity
    container_registry_managed_identity_client_id = var.container.identity_client_id

    application_stack {
      docker_image_name        = var.container.image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = var.auto_heal.enabled ? [var.auto_heal] : []
      content {
        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = "00:01:00"
        }
        trigger {
          dynamic "requests" {
            for_each = auto_heal_setting.value.request_count != null ? [1] : []
            content {
              count    = auto_heal_setting.value.request_count
              interval = auto_heal_setting.value.request_interval
            }
          }
          dynamic "slow_request" {
            for_each = auto_heal_setting.value.slow_request_count != null ? [1] : []
            content {
              count      = auto_heal_setting.value.slow_request_count
              interval   = auto_heal_setting.value.slow_request_interval
              time_taken = auto_heal_setting.value.slow_request_time
            }
          }
          status_code {
            count             = auto_heal_setting.value.status_code_count
            interval          = auto_heal_setting.value.status_code_interval
            status_code_range = auto_heal_setting.value.status_code_range
          }
        }
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
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  tags = local.tags
}

# Blue/green control: when promote_to_production = true, the slot is swapped into
# production. Setting it back to false swaps back (rollback). Destruction of this
# resource restores the original active slot.
resource "azurerm_web_app_active_slot" "staging" {
  count = local.slot_enabled && var.deployment_slot.promote_to_production ? 1 : 0

  slot_id = azurerm_linux_web_app_slot.staging[0].id
}

# -----------------------------------------------------------------------------
# Capacity: autoscaling
# -----------------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "main" {
  count = var.autoscale.enabled ? 1 : 0

  name                = "autoscale-${var.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_service_plan.main.id

  profile {
    name = "default"

    capacity {
      default = local.autoscale_default
      minimum = local.autoscale_min
      maximum = local.autoscale_max
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale.scale_out_cpu_threshold
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
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale.scale_in_cpu_threshold
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale.scale_out_memory_threshold
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
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale.scale_in_memory_threshold
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = local.tags
}
