resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_service_plan" "this" {
  name                   = "asp-${local.name_prefix}"
  resource_group_name    = local.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.capacity.sku_name
  worker_count           = local.effective_worker_count
  zone_balancing_enabled = local.supports_zone_bal ? var.availability.zone_redundant : false
  tags                   = local.common_tags

  lifecycle {
    # Autoscale dynamically adjusts worker_count at runtime.
    ignore_changes = [worker_count]
  }

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_linux_web_app" "this" {
  name                                           = local.web_app_name
  resource_group_name                            = local.resource_group_name
  location                                       = var.location
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = var.availability.public_network_access_enabled
  virtual_network_subnet_id                      = var.availability.vnet_subnet_id
  vnet_image_pull_enabled                        = var.availability.vnet_subnet_id != null ? var.availability.vnet_image_pull_enabled : false
  client_affinity_enabled                        = var.health.client_affinity_enabled
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  app_settings = merge(
    local.base_app_settings,
    {
      APP_SLOT = "production"
    },
  )

  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }

  site_config {
    always_on                               = local.effective_always_on
    app_command_line                        = var.container.command
    container_registry_use_managed_identity = var.container.use_managed_identity
    container_registry_managed_identity_client_id = (
      var.container.use_managed_identity ? var.container.managed_identity_client_id : null
    )
    ftps_state                        = "Disabled"
    health_check_path                 = var.health.path
    health_check_eviction_time_in_min = var.health.eviction_time_minutes
    http2_enabled                     = var.health.http2_enabled
    load_balancing_mode               = "LeastRequests"
    minimum_tls_version               = var.health.minimum_tls_version
    scm_minimum_tls_version           = var.health.minimum_tls_version
    scm_use_main_ip_restriction       = length(var.availability.ip_restrictions) > 0
    use_32_bit_worker                 = false
    vnet_route_all_enabled            = var.availability.vnet_subnet_id != null ? var.availability.vnet_route_all_enabled : false

    application_stack {
      docker_image_name        = var.container.image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.use_managed_identity ? null : var.container.registry_username
      docker_registry_password = var.container.use_managed_identity ? null : var.container_registry_password
    }

    dynamic "cors" {
      for_each = length(var.health.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins = var.health.cors_allowed_origins
      }
    }

    dynamic "ip_restriction" {
      for_each = var.availability.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
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
        retention_in_mb   = 100
      }
    }
  }

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = local.effective_slots ? 1 : 0

  name                                           = var.rollout.staging_slot_name
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  public_network_access_enabled                  = var.availability.public_network_access_enabled
  virtual_network_subnet_id                      = var.availability.vnet_subnet_id
  vnet_image_pull_enabled                        = var.availability.vnet_subnet_id != null ? var.availability.vnet_image_pull_enabled : false
  client_affinity_enabled                        = var.health.client_affinity_enabled
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  app_settings = merge(
    local.base_app_settings,
    {
      APP_SLOT = var.rollout.staging_slot_name
    },
    var.rollout.staging_app_settings,
  )

  site_config {
    always_on                               = local.effective_always_on
    app_command_line                        = var.container.command
    auto_swap_slot_name                     = var.rollout.auto_swap_to_production ? "production" : null
    container_registry_use_managed_identity = var.container.use_managed_identity
    container_registry_managed_identity_client_id = (
      var.container.use_managed_identity ? var.container.managed_identity_client_id : null
    )
    ftps_state                        = "Disabled"
    health_check_path                 = var.health.path
    health_check_eviction_time_in_min = var.health.eviction_time_minutes
    http2_enabled                     = var.health.http2_enabled
    load_balancing_mode               = "LeastRequests"
    minimum_tls_version               = var.health.minimum_tls_version
    scm_minimum_tls_version           = var.health.minimum_tls_version
    scm_use_main_ip_restriction       = length(var.availability.ip_restrictions) > 0
    use_32_bit_worker                 = false
    vnet_route_all_enabled            = var.availability.vnet_subnet_id != null ? var.availability.vnet_route_all_enabled : false

    application_stack {
      docker_image_name        = coalesce(var.rollout.staging_container_image, var.container.image)
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.use_managed_identity ? null : var.container.registry_username
      docker_registry_password = var.container.use_managed_identity ? null : var.container_registry_password
    }

    dynamic "cors" {
      for_each = length(var.health.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins = var.health.cors_allowed_origins
      }
    }

    dynamic "ip_restriction" {
      for_each = var.availability.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
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
        retention_in_mb   = 100
      }
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.effective_autoscale ? 1 : 0

  name                = "autoscale-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default-capacity"

    capacity {
      default = local.effective_worker_count
      minimum = local.effective_min_instances
      maximum = local.effective_max_instances
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
        threshold          = var.capacity.cpu_scale_out_pct
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
        operator           = "GreaterThan"
        threshold          = var.capacity.memory_scale_out_pct
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
        threshold          = var.capacity.cpu_scale_in_pct
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

check "sku_capabilities" {
  assert {
    condition     = !(var.availability.zone_redundant && !local.supports_zone_bal)
    error_message = "Zone redundancy requested, but sku_name '${var.capacity.sku_name}' is not a Premium tier (e.g. P1v3); zone_balancing_enabled will be disabled."
  }

  assert {
    condition     = !(var.rollout.staging_slot_enabled && !local.supports_slots)
    error_message = "Staging slot requested, but sku_name '${var.capacity.sku_name}' does not support deployment slots (requires Standard or Premium)."
  }
}
