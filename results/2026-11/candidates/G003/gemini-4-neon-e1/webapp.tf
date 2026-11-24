# =============================================================================
# Production Containerized HTTP API (Linux App Service)
# =============================================================================

resource "azurerm_linux_web_app" "this" {
  name                = local.web_app_name
  resource_group_name = local.resource_group_name
  location            = local.location
  service_plan_id     = local.service_plan_id

  # Hardened HTTP API defaults
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = var.network.public_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.network.vnet_image_pull_enabled
  key_vault_reference_identity_id                = var.identity.key_vault_reference_identity_id

  app_settings = local.production_app_settings
  tags         = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.identity.user_assigned_identity_ids) > 0 ? var.identity.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = true
    use_32_bit_worker                             = false
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    scm_use_main_ip_restriction                   = true
    load_balancing_mode                           = var.health.load_balancing_mode
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    vnet_route_all_enabled                        = var.network.vnet_integration_subnet_id != null
    container_registry_use_managed_identity       = local.use_managed_identity_for_acr
    container_registry_managed_identity_client_id = local.use_managed_identity_for_acr ? var.identity.acr_pull_identity_client_id : null
    app_command_line                              = var.container.startup_command
    ip_restriction_default_action                 = length(var.network.ip_restrictions) > 0 ? "Deny" : "Allow"
    scm_ip_restriction_default_action             = length(var.network.ip_restrictions) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name        = var.container.image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.network.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.subnet_id
        service_tag               = ip_restriction.value.service_tag
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
      }
    }

    dynamic "cors" {
      for_each = length(var.network.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.network.cors_allowed_origins
        support_credentials = var.network.cors_support_credentials
      }
    }
  }

  # Enable built-in diagnostic streams so live log tailing works during incident response
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

  # Pin slot-scoped settings so swaps never leak environment/slot identifiers
  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }
}

# =============================================================================
# Staging Deployment Slot (Zero-Downtime Rollouts)
# =============================================================================

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.rollouts.enable_staging_slot ? 1 : 0

  name           = var.rollouts.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = local.staging_public_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.network.vnet_image_pull_enabled
  key_vault_reference_identity_id                = var.identity.key_vault_reference_identity_id

  app_settings = local.staging_app_settings
  tags         = merge(local.common_tags, { slot = var.rollouts.staging_slot_name })

  identity {
    type         = local.identity_type
    identity_ids = length(var.identity.user_assigned_identity_ids) > 0 ? var.identity.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = true
    use_32_bit_worker                             = false
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    scm_use_main_ip_restriction                   = true
    load_balancing_mode                           = var.health.load_balancing_mode
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    vnet_route_all_enabled                        = var.network.vnet_integration_subnet_id != null
    container_registry_use_managed_identity       = local.use_managed_identity_for_acr
    container_registry_managed_identity_client_id = local.use_managed_identity_for_acr ? var.identity.acr_pull_identity_client_id : null
    app_command_line                              = var.container.startup_command
    auto_swap_slot_name                           = var.rollouts.auto_swap_enabled ? "production" : null
    ip_restriction_default_action                 = length(local.staging_ip_restrictions) > 0 ? "Deny" : "Allow"
    scm_ip_restriction_default_action             = length(local.staging_ip_restrictions) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.staging_ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.subnet_id
        service_tag               = ip_restriction.value.service_tag
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
      }
    }

    dynamic "cors" {
      for_each = length(var.network.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.network.cors_allowed_origins
        support_credentials = var.network.cors_support_credentials
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
}
