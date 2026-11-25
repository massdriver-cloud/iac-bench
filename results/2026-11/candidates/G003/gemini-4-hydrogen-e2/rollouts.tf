resource "azurerm_linux_web_app_slot" "staging" {
  count = local.staging_slot_enabled ? 1 : 0

  name                                           = var.rollout.slot_name
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  public_network_access_enabled                  = var.availability.public_network_access_enabled
  virtual_network_subnet_id                      = var.availability.vnet_subnet_id
  vnet_image_pull_enabled                        = var.availability.vnet_image_pull_enabled
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = local.always_on_enabled
    use_32_bit_worker                             = false
    http2_enabled                                 = true
    minimum_tls_version                           = var.minimum_tls_version
    ftps_state                                    = "Disabled"
    vnet_route_all_enabled                        = var.availability.vnet_subnet_id != null ? var.availability.vnet_route_all_enabled : false
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.path != null ? var.health.eviction_time_in_min : null
    load_balancing_mode                           = var.availability.load_balancing_mode
    app_command_line                              = var.container.startup_command
    auto_swap_slot_name                           = var.rollout.auto_swap_enabled ? "production" : null
    container_registry_use_managed_identity       = local.use_managed_identity_for_registry
    container_registry_managed_identity_client_id = var.container.managed_identity_client_id
    ip_restriction_default_action                 = var.availability.ip_restriction_default_action
    scm_use_main_ip_restriction                   = local.scm_use_main_ip_restriction

    application_stack {
      docker_registry_url      = local.docker_registry_url
      docker_image_name        = local.staging_docker_image_name
      docker_registry_username = local.use_managed_identity_for_registry ? null : var.container.registry_username
      docker_registry_password = local.use_managed_identity_for_registry ? null : var.container.registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.availability.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.subnet_id
        service_tag               = ip_restriction.value.service_tag
      }
    }

    dynamic "cors" {
      for_each = var.cors != null ? [var.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  app_settings = local.staging_app_settings

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
      file_system_level = var.observability.application_log_level
    }
  }
}

resource "azurerm_role_assignment" "slot_acr_pull" {
  count = local.staging_slot_enabled && var.container.acr_id != null ? 1 : 0

  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
