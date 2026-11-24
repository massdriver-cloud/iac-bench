# ------------------------------------------------------------------------------
# Staging Deployment Slot (Blue/Green & Zero-Downtime Swaps)
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.rollout.staging_slot_enabled ? 1 : 0

  name           = var.rollout.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.networking.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.networking.vnet_integration_subnet_id != null && var.networking.vnet_image_pull_enabled
  key_vault_reference_identity_id                = var.security.key_vault_reference_identity_id

  identity {
    type         = local.identity_type
    identity_ids = local.identity_ids
  }

  site_config {
    always_on                                     = true
    use_32_bit_worker                             = false
    http2_enabled                                 = true
    load_balancing_mode                           = "LeastRequests"
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = var.security.minimum_tls_version
    scm_minimum_tls_version                       = var.security.minimum_tls_version
    websockets_enabled                            = var.networking.websockets_enabled
    vnet_route_all_enabled                        = var.networking.vnet_integration_subnet_id != null
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_minutes
    container_registry_use_managed_identity       = local.use_acr_managed_identity
    container_registry_managed_identity_client_id = local.use_acr_managed_identity ? var.container.managed_identity_client_id : null
    app_command_line                              = var.container.startup_command
    ip_restriction_default_action                 = var.networking.ip_restriction_default_action

    application_stack {
      docker_image_name        = coalesce(var.rollout.staging_image, var.container.image)
      docker_registry_url      = var.container.registry_url
      docker_registry_username = local.use_acr_managed_identity ? null : var.container.registry_username
      docker_registry_password = local.use_acr_managed_identity ? null : var.container_registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = var.health.auto_heal_enabled ? [1] : []
      content {
        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = "00:02:00"
        }
        trigger {
          status_code {
            count             = var.health.auto_heal_5xx_count
            interval          = var.health.auto_heal_5xx_interval
            status_code_range = "500-599"
          }
        }
      }
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

    dynamic "cors" {
      for_each = var.networking.cors != null ? [var.networking.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.observability.app_log_level
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  app_settings = local.staging_app_settings
  tags         = local.common_tags

  lifecycle {
    precondition {
      condition     = !local.manage_service_plan || !startswith(var.capacity.sku_name, "B")
      error_message = "Deployment slots require a Standard, Premium, or Isolated SKU (Basic SKUs B1-B3 do not support deployment slots)."
    }
  }
}

# ------------------------------------------------------------------------------
# RBAC: ACR Pull & Key Vault Secrets Access (Staging Slot Identity)
# ------------------------------------------------------------------------------

resource "azurerm_role_assignment" "staging_acr_pull" {
  count = var.rollout.staging_slot_enabled && var.container.acr_id != null ? 1 : 0

  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_key_vault_secrets_user" {
  count = var.rollout.staging_slot_enabled && var.security.key_vault_id != null ? 1 : 0

  scope                = var.security.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
