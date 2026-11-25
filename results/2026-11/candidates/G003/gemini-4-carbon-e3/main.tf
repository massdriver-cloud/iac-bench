# -----------------------------------------------------------------------------
# Resource Group & Naming Suffix
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = coalesce(var.resource_group_name, "rg-${local.name_prefix}")
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = coalesce(var.resource_group_name, "rg-${local.name_prefix}")
}

resource "random_string" "app_suffix" {
  count   = var.custom_app_name == null ? 1 : 0
  length  = 5
  upper   = false
  special = false
}

# -----------------------------------------------------------------------------
# App Service Plan (Compute & Availability Zone Redundancy)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count                    = local.create_service_plan ? 1 : 0
  name                     = "asp-${local.name_prefix}"
  resource_group_name      = local.resource_group_name
  location                 = local.location
  os_type                  = "Linux"
  sku_name                 = var.capacity.sku_name
  worker_count             = var.capacity.min_instances
  zone_balancing_enabled   = local.effective_zone_redundant
  per_site_scaling_enabled = var.capacity.per_site_scaling_enabled
  tags                     = local.tags

  lifecycle {
    precondition {
      condition     = !local.effective_zone_redundant || (local.sku_supports_zones && var.capacity.min_instances >= 2)
      error_message = "Zone redundancy requires a zone-capable SKU (Premium v2/v3 or Isolated v2) and capacity.min_instances >= 2."
    }
  }
}

# -----------------------------------------------------------------------------
# Production Linux Web App
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                                           = local.app_name
  resource_group_name                            = local.resource_group_name
  location                                       = local.location
  service_plan_id                                = local.service_plan_id
  https_only                                     = true
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.network.vnet_image_pull_enabled
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  app_settings                                   = local.production_app_settings
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
    container_registry_use_managed_identity       = var.container.acr_use_managed_identity
    container_registry_managed_identity_client_id = var.container.acr_managed_identity_client_id
    vnet_route_all_enabled                        = var.network.vnet_integration_subnet_id != null ? var.network.vnet_route_all_enabled : false
    ip_restriction_default_action                 = var.network.ip_restriction_default_action
    scm_ip_restriction_default_action             = var.network.scm_ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.network.scm_use_main_ip_restriction

    application_stack {
      docker_image_name        = var.container.image
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

  sticky_settings {
    app_setting_names       = local.sticky_app_setting_names
    connection_string_names = length(var.rollout.sticky_connection_string_names) > 0 ? var.rollout.sticky_connection_string_names : null
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
}

# -----------------------------------------------------------------------------
# Private Endpoint (Optional Inbound Isolation)
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "this" {
  count               = var.network.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-${local.name_prefix}"
  location            = local.location
  resource_group_name = local.resource_group_name
  subnet_id           = var.network.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.name_prefix}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.network.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = var.network.private_dns_zone_ids
    }
  }
}

# -----------------------------------------------------------------------------
# Custom Domains & App Service Managed TLS Certificates
# -----------------------------------------------------------------------------

resource "azurerm_app_service_custom_hostname_binding" "this" {
  for_each            = local.custom_domains_map
  hostname            = each.key
  app_service_name    = azurerm_linux_web_app.this.name
  resource_group_name = local.resource_group_name
}

resource "azurerm_app_service_managed_certificate" "this" {
  for_each                   = { for k, v in local.custom_domains_map : k => v if v.managed_certificate_enabled }
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.this[each.key].id
  tags                       = local.tags
}

resource "azurerm_app_service_certificate_binding" "this" {
  for_each            = { for k, v in local.custom_domains_map : k => v if v.managed_certificate_enabled }
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.this[each.key].id
  certificate_id      = azurerm_app_service_managed_certificate.this[each.key].id
  ssl_state           = "SniEnabled"
}

# -----------------------------------------------------------------------------
# Managed Identity RBAC Assignments (ACR Pull & Key Vault Secrets)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_acr_pull" {
  count                = var.container.acr_id != null ? 1 : 0
  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "app_kv_secrets_user" {
  count                = var.key_vault_id != null && var.key_vault_reference_identity_id == null ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}
