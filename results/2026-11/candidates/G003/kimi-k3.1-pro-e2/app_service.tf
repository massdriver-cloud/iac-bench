resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = local.service_plan_id

  enabled                                        = true
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = local.public_network_access_enabled
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.vnet_image_pull_enabled
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.app_settings
  tags         = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = var.user_assigned_identity_ids
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    ftps_state                                    = "Disabled"
    remote_debugging_enabled                      = false
    use_32_bit_worker                             = false
    websockets_enabled                            = false
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_min
    vnet_route_all_enabled                        = var.vnet_route_all_enabled
    container_registry_use_managed_identity       = var.container_registry_use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry_managed_identity_client_id

    ip_restriction_default_action = var.ip_restriction_default_action
    scm_use_main_ip_restriction   = true

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        description               = ip_restriction.value.description
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
      }
    }

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.application_log_level
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
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
      condition     = !var.container_registry_use_managed_identity || (var.container_registry_username == null && var.container_registry_password == null)
      error_message = "Registry username/password cannot be combined with managed-identity registry pull."
    }

    precondition {
      condition     = var.container_registry_managed_identity_client_id == null || var.container_registry_use_managed_identity
      error_message = "container_registry_managed_identity_client_id requires container_registry_use_managed_identity=true."
    }

    precondition {
      condition     = var.container_registry_managed_identity_principal_id == null || var.container_registry_managed_identity_client_id != null
      error_message = "container_registry_managed_identity_principal_id requires container_registry_managed_identity_client_id."
    }

    precondition {
      condition     = var.container_registry_id == null || var.container_registry_managed_identity_client_id == null || var.container_registry_managed_identity_principal_id != null
      error_message = "Provide container_registry_managed_identity_principal_id so the selected user-assigned identity can receive AcrPull."
    }

    precondition {
      condition     = !var.vnet_image_pull_enabled || var.vnet_integration_subnet_id != null
      error_message = "vnet_image_pull_enabled requires vnet_integration_subnet_id."
    }

    precondition {
      condition     = length(var.private_dns_zone_ids) == 0 || var.private_endpoint_subnet_id != null
      error_message = "private_dns_zone_ids requires private_endpoint_subnet_id."
    }

    precondition {
      condition = alltrue([
        for rule in var.ip_restrictions : length([
          for source in [rule.ip_address, rule.service_tag, rule.virtual_network_subnet_id] : source
          if source != null && source != ""
        ]) == 1
      ])
      error_message = "Each IP restriction must specify exactly one of ip_address, service_tag or virtual_network_subnet_id."
    }

    precondition {
      condition     = alltrue([for rule in var.ip_restrictions : contains(["Allow", "Deny"], rule.action) && rule.priority >= 1])
      error_message = "IP restriction actions must be Allow or Deny and priorities must be positive."
    }

    precondition {
      condition     = length(distinct([for rule in var.ip_restrictions : rule.name])) == length(var.ip_restrictions) && length(distinct([for rule in var.ip_restrictions : rule.priority])) == length(var.ip_restrictions)
      error_message = "IP restriction names and priorities must each be unique."
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.deployment_slot_enabled ? 1 : 0

  name           = var.deployment_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  enabled                                        = true
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = local.public_network_access_enabled
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.vnet_image_pull_enabled
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.app_settings
  tags         = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = var.user_assigned_identity_ids
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    ftps_state                                    = "Disabled"
    remote_debugging_enabled                      = false
    use_32_bit_worker                             = false
    websockets_enabled                            = false
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_min
    vnet_route_all_enabled                        = var.vnet_route_all_enabled
    container_registry_use_managed_identity       = var.container_registry_use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry_managed_identity_client_id

    ip_restriction_default_action = var.ip_restriction_default_action
    scm_use_main_ip_restriction   = true

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        description               = ip_restriction.value.description
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
      }
    }

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.application_log_level
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  lifecycle {
    # Pipelines deploy candidate images to staging. OpenTofu owns the slot and
    # its configuration but must not roll a candidate back on the next apply.
    ignore_changes = [site_config[0].application_stack[0].docker_image_name]
  }
}
