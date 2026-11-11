resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  service_plan_id     = local.service_plan_id

  enabled                                        = true
  https_only                                     = true
  client_affinity_enabled                        = false
  client_certificate_enabled                     = false
  public_network_access_enabled                  = var.public_network_access_enabled
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  virtual_network_subnet_id                      = var.virtual_network_subnet_id
  vnet_image_pull_enabled                        = var.vnet_image_pull_enabled
  app_settings                                   = local.production_app_settings
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on                         = true
    app_command_line                  = var.app_command_line
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path == null ? null : var.health_check_eviction_time_in_minutes
    http2_enabled                     = true
    ip_restriction_default_action     = var.ip_restriction_default_action
    load_balancing_mode               = "LeastRequests"
    minimum_tls_version               = "1.2"
    remote_debugging_enabled          = false
    scm_minimum_tls_version           = "1.2"
    scm_use_main_ip_restriction       = true
    use_32_bit_worker                 = false
    vnet_route_all_enabled            = var.vnet_route_all_enabled
    websockets_enabled                = false

    container_registry_use_managed_identity       = local.use_registry_managed_identity
    container_registry_managed_identity_client_id = local.use_registry_managed_identity ? azurerm_user_assigned_identity.this.client_id : null

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        description               = ip_restriction.value.description
      }
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = var.cors_support_credentials
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.app_service_log_level
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  lifecycle {
    precondition {
      condition     = (var.container_registry_username == null) == (var.container_registry_password == null)
      error_message = "container_registry_username and container_registry_password must be supplied together."
    }

    precondition {
      condition     = !var.deployment_slot_enabled || !contains(["F1", "D1", "B1", "B2", "B3"], upper(var.plan_sku_name))
      error_message = "A Standard or Premium SKU is required when deployment_slot_enabled is true."
    }

    precondition {
      condition = alltrue([
        for rule in var.ip_restrictions : length(compact([
          rule.ip_address,
          rule.service_tag,
          rule.virtual_network_subnet_id,
        ])) == 1
      ])
      error_message = "Each IP restriction must specify exactly one non-empty source: ip_address, service_tag, or virtual_network_subnet_id."
    }

    precondition {
      condition     = !var.cors_support_credentials || !contains(var.cors_allowed_origins, "*")
      error_message = "CORS credentials cannot be combined with the wildcard origin."
    }

    precondition {
      condition     = (!var.vnet_route_all_enabled && !var.vnet_image_pull_enabled) || var.virtual_network_subnet_id != null
      error_message = "virtual_network_subnet_id is required when VNet routing or VNet image pull is enabled."
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
