resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

locals {
  effective_resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
}

# -----------------------------------------------------------------------------
# App Service Plan (Compute & Availability Boundary)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count                    = local.create_service_plan ? 1 : 0
  name                     = local.plan_name
  resource_group_name      = local.effective_resource_group_name
  location                 = var.location
  os_type                  = "Linux"
  sku_name                 = var.capacity.sku_name
  worker_count             = var.capacity.min_instances
  per_site_scaling_enabled = var.capacity.per_site_scaling_enabled
  zone_balancing_enabled   = var.availability.zone_redundant
  tags                     = local.common_tags

  lifecycle {
    precondition {
      condition     = !var.availability.zone_redundant || (local.sku_supports_zones && var.capacity.min_instances >= 2)
      error_message = "availability.zone_redundant = true requires a zone-capable Premium (P1v2+, P1v3+, P1v4+) or Isolated (I1v2+) SKU and capacity.min_instances >= 2."
    }
  }
}

# -----------------------------------------------------------------------------
# Production Linux Web App (Containerized HTTP Service)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                                           = local.web_app_name
  resource_group_name                            = local.effective_resource_group_name
  location                                       = var.location
  service_plan_id                                = local.service_plan_id
  https_only                                     = var.availability.https_only
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  virtual_network_subnet_id                      = var.networking.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = local.vnet_image_pull_active
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.production_app_settings
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = local.always_on_effective
    use_32_bit_worker                             = false
    http2_enabled                                 = var.availability.http2_enabled
    websockets_enabled                            = var.container.websockets_enabled
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    ftps_state                                    = "Disabled"
    app_command_line                              = var.container.command
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.path != null ? var.health.eviction_time_in_min : null
    container_registry_use_managed_identity       = local.use_acr_managed_id
    container_registry_managed_identity_client_id = local.use_acr_managed_id ? var.container.managed_identity_client_id : null
    vnet_route_all_enabled                        = var.networking.vnet_integration_subnet_id != null ? var.networking.vnet_route_all_enabled : false
    ip_restriction_default_action                 = local.ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.networking.scm_use_main_ip_restriction
    scm_ip_restriction_default_action             = length(local.scm_ip_restrictions) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name        = var.container.image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = local.use_acr_managed_id ? null : var.container.registry_username
      docker_registry_password = local.use_acr_managed_id ? null : var.container_registry_password
    }

    dynamic "cors" {
      for_each = var.networking.cors != null ? [var.networking.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id

        dynamic "headers" {
          for_each = ip_restriction.value.x_azure_fdid != null ? [ip_restriction.value.x_azure_fdid] : []
          content {
            x_azure_fdid = headers.value
          }
        }
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = local.scm_ip_restrictions
      content {
        name       = scm_ip_restriction.value.name
        priority   = scm_ip_restriction.value.priority
        action     = scm_ip_restriction.value.action
        ip_address = scm_ip_restriction.value.ip_address
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = local.has_sticky_settings ? [1] : []
    content {
      app_setting_names       = length(local.sticky_app_setting_names) > 0 ? local.sticky_app_setting_names : null
      connection_string_names = length(var.rollout.sticky_connection_string_names) > 0 ? var.rollout.sticky_connection_string_names : null
    }
  }

  dynamic "connection_string" {
    for_each = local.connection_string_names
    content {
      name  = connection_string.value
      type  = var.connection_strings[connection_string.value].type
      value = var.connection_strings[connection_string.value].value
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
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Pre-Production Rollout Slot (Safe Staged Rollouts & Warmup Swaps)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = local.staging_slot_enabled ? 1 : 0
  name                                           = var.rollout.slot_name
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = var.availability.https_only
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  virtual_network_subnet_id                      = var.networking.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = local.vnet_image_pull_active
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.staging_app_settings
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = local.always_on_effective
    use_32_bit_worker                             = false
    http2_enabled                                 = var.availability.http2_enabled
    websockets_enabled                            = var.container.websockets_enabled
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    ftps_state                                    = "Disabled"
    app_command_line                              = var.container.command
    auto_swap_slot_name                           = var.rollout.auto_swap_enabled ? "production" : null
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.path != null ? var.health.eviction_time_in_min : null
    container_registry_use_managed_identity       = local.use_acr_managed_id
    container_registry_managed_identity_client_id = local.use_acr_managed_id ? var.container.managed_identity_client_id : null
    vnet_route_all_enabled                        = var.networking.vnet_integration_subnet_id != null ? var.networking.vnet_route_all_enabled : false
    ip_restriction_default_action                 = local.ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.networking.scm_use_main_ip_restriction
    scm_ip_restriction_default_action             = length(local.scm_ip_restrictions) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name        = var.container.image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = local.use_acr_managed_id ? null : var.container.registry_username
      docker_registry_password = local.use_acr_managed_id ? null : var.container_registry_password
    }

    dynamic "cors" {
      for_each = var.networking.cors != null ? [var.networking.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id

        dynamic "headers" {
          for_each = ip_restriction.value.x_azure_fdid != null ? [ip_restriction.value.x_azure_fdid] : []
          content {
            x_azure_fdid = headers.value
          }
        }
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = local.scm_ip_restrictions
      content {
        name       = scm_ip_restriction.value.name
        priority   = scm_ip_restriction.value.priority
        action     = scm_ip_restriction.value.action
        ip_address = scm_ip_restriction.value.ip_address
      }
    }
  }

  dynamic "connection_string" {
    for_each = local.connection_string_names
    content {
      name  = connection_string.value
      type  = var.connection_strings[connection_string.value].type
      value = var.connection_strings[connection_string.value].value
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
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.sku_supports_slots
      error_message = "rollout.staging_slot_enabled = true requires a Standard, Premium, or Isolated App Service Plan SKU (current SKU: ${var.capacity.sku_name})."
    }
  }
}

# -----------------------------------------------------------------------------
# Managed Identity RBAC Assignments (ACR Pull & Key Vault Secrets)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull_production" {
  count                = var.container.acr_id != null && var.container.managed_identity_client_id == null ? 1 : 0
  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count                = var.container.acr_id != null && var.container.managed_identity_client_id == null && local.staging_slot_enabled ? 1 : 0
  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "kv_secrets_production" {
  count                = var.key_vault_id != null && var.key_vault_reference_identity_id == null ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "kv_secrets_staging" {
  count                = var.key_vault_id != null && var.key_vault_reference_identity_id == null && local.staging_slot_enabled ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
