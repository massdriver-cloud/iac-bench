# ------------------------------------------------------------------------------
# Staging Deployment Slot (Blue/Green Zero-Downtime Rollouts)
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.rollout.staging_slot_enabled ? 1 : 0

  name           = var.rollout.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  https_only                                     = true
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.networking.vnet_subnet_id
  vnet_image_pull_enabled                        = var.container.vnet_image_pull_enabled

  app_settings = local.staging_app_settings
  tags         = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = local.effective_always_on
    use_32_bit_worker                             = local.use_32_bit_worker
    ftps_state                                    = "Disabled"
    http2_enabled                                 = var.networking.http2_enabled
    websockets_enabled                            = var.networking.websockets_enabled
    minimum_tls_version                           = var.networking.minimum_tls_version
    scm_minimum_tls_version                       = var.networking.minimum_tls_version
    load_balancing_mode                           = var.availability.load_balancing_mode
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.path != null ? var.health.eviction_time_in_min : null
    app_command_line                              = var.container.start_command
    auto_swap_slot_name                           = var.rollout.auto_swap_enabled ? "production" : null
    container_registry_use_managed_identity       = local.use_acr_managed_identity
    container_registry_managed_identity_client_id = local.use_acr_managed_identity ? var.container.acr_managed_identity_client_id : null
    vnet_route_all_enabled                        = var.networking.vnet_subnet_id != null ? var.networking.vnet_route_all_enabled : false
    ip_restriction_default_action                 = var.networking.ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.networking.scm_use_main_ip_restriction
    scm_ip_restriction_default_action             = var.networking.scm_ip_restriction_default_action

    application_stack {
      docker_image_name        = local.staging_docker_image_name
      docker_registry_url      = local.staging_registry_url
      docker_registry_username = local.use_acr_managed_identity ? null : var.container.registry_username
      docker_registry_password = local.use_acr_managed_identity ? null : var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.networking.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.networking.scm_ip_restrictions
      content {
        name                      = scm_ip_restriction.value.name
        priority                  = scm_ip_restriction.value.priority
        action                    = scm_ip_restriction.value.action
        ip_address                = scm_ip_restriction.value.ip_address
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
      }
    }

    dynamic "cors" {
      for_each = var.networking.cors != null ? [var.networking.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  logs {
    detailed_error_messages = var.observability.detailed_error_messages
    failed_request_tracing  = var.observability.failed_request_tracing

    application_logs {
      file_system_level = var.observability.application_log_level
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = 35
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Optional ACR Pull RBAC for Staging Slot Managed Identity
# ------------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = var.rollout.staging_slot_enabled && var.container.acr_id != null ? 1 : 0

  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
