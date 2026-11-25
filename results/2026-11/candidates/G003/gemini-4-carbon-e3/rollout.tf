# -----------------------------------------------------------------------------
# Staging Deployment Slot (Safe Rollouts & Warmup-Gated Swaps)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = local.effective_staging_slot_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.network.vnet_image_pull_enabled
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  app_settings                                   = local.staging_app_settings
  tags                                           = local.tags

  identity {
    type         = local.identity_type
    identity_ids = local.has_user_assigned_identities ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = var.availability.always_on
    use_32_bit_worker                             = false
    ftps_state                                    = "Disabled"
    http2_enabled                                 = var.availability.http2_enabled
    websockets_enabled                            = var.container.websockets_enabled
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    app_command_line                              = var.container.startup_command
    auto_swap_slot_name                           = var.rollout.auto_swap_enabled ? "production" : null
    container_registry_use_managed_identity       = var.container.acr_use_managed_identity
    container_registry_managed_identity_client_id = var.container.acr_managed_identity_client_id
    vnet_route_all_enabled                        = var.network.vnet_integration_subnet_id != null ? var.network.vnet_route_all_enabled : false
    ip_restriction_default_action                 = var.network.ip_restriction_default_action
    scm_ip_restriction_default_action             = var.network.scm_ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.network.scm_use_main_ip_restriction

    application_stack {
      docker_image_name        = coalesce(var.rollout.staging_image, var.container.image)
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = var.availability.auto_heal_enabled ? [1] : []
      content {
        trigger {
          status_code {
            status_code_range = "500-599"
            count             = var.availability.auto_heal_5xx_count
            interval          = var.availability.auto_heal_5xx_interval
          }

          slow_request {
            time_taken = var.availability.auto_heal_slow_request_time
            count      = var.availability.auto_heal_slow_request_count
            interval   = var.availability.auto_heal_slow_request_interval
          }
        }

        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = var.availability.auto_heal_startup_grace_period
        }
      }
    }

    dynamic "ip_restriction" {
      for_each = var.network.ip_restrictions
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
      for_each = var.network.cors != null ? [var.network.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = var.observability.http_logs_max_size_mb
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !local.create_service_plan || local.sku_supports_slots
      error_message = "Deployment slots require a Standard (S1-S3), Premium (P*v2/v3), or Isolated (I*v2) App Service Plan SKU."
    }
  }
}

resource "azurerm_role_assignment" "staging_acr_pull" {
  count                = local.effective_staging_slot_enabled && var.container.acr_id != null ? 1 : 0
  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_kv_secrets_user" {
  count                = local.effective_staging_slot_enabled && var.key_vault_id != null && var.key_vault_reference_identity_id == null ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
