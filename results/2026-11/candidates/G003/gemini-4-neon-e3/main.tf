# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = coalesce(var.resource_group_name, local.default_resource_group)
  location = var.location
  tags     = local.common_tags
}

# ------------------------------------------------------------------------------
# Linux App Service Plan
# ------------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count = local.manage_service_plan ? 1 : 0

  name                   = local.service_plan_name
  resource_group_name    = local.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.capacity.sku_name
  worker_count           = var.capacity.min_instances
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = local.common_tags

  # Autoscale dynamically adjusts worker_count at runtime; ignore drift so
  # subsequent plans do not scale down an active traffic spike.
  lifecycle {
    ignore_changes = [worker_count]
  }
}

# ------------------------------------------------------------------------------
# Linux Web App (Production Slot)
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = local.app_name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = local.service_plan_id

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
      docker_image_name        = var.container.image
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

  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }

  app_settings = local.production_app_settings
  tags         = local.common_tags
}

# ------------------------------------------------------------------------------
# RBAC: ACR Pull & Key Vault Secrets Access (Production Identity)
# ------------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container.acr_id != null ? 1 : 0

  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  count = var.security.key_vault_id != null ? 1 : 0

  scope                = var.security.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

# ------------------------------------------------------------------------------
# Optional Custom Domains & Managed TLS Certificates
# ------------------------------------------------------------------------------

resource "azurerm_app_service_custom_hostname_binding" "this" {
  for_each = toset(var.networking.custom_domains)

  hostname            = each.value
  app_service_name    = azurerm_linux_web_app.this.name
  resource_group_name = local.resource_group_name

  lifecycle {
    ignore_changes = [ssl_state, thumbprint]
  }
}

resource "azurerm_app_service_managed_certificate" "this" {
  for_each = toset(var.networking.custom_domains)

  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.this[each.key].id
  tags                       = local.common_tags
}

resource "azurerm_app_service_certificate_binding" "this" {
  for_each = toset(var.networking.custom_domains)

  hostname_binding_id = azurerm_app_service_custom_hostname_binding.this[each.key].id
  certificate_id      = azurerm_app_service_managed_certificate.this[each.key].id
  ssl_state           = "SniEnabled"
}
