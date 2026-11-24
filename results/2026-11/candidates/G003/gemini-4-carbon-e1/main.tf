data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Resource Group (Dedicated per service unless existing_resource_group_name set)
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# Linux App Service Plan (Dedicated unless capacity.existing_service_plan_id set)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count = local.create_service_plan ? 1 : 0

  name                     = local.service_plan_name
  resource_group_name      = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  location                 = local.location
  os_type                  = "Linux"
  sku_name                 = var.capacity.sku_name
  worker_count             = var.capacity.min_instances
  zone_balancing_enabled   = var.availability.zone_balancing_enabled
  per_site_scaling_enabled = var.capacity.per_site_scaling_enabled
  tags                     = local.common_tags
}

# -----------------------------------------------------------------------------
# Production Linux Web App
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                                           = local.web_app_name
  resource_group_name                            = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  location                                       = local.location
  service_plan_id                                = local.service_plan_id
  https_only                                     = true
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = local.vnet_integrated
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = var.rollout.basic_auth_publishing_enabled
  app_settings                                   = local.production_app_settings
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = var.availability.always_on
    http2_enabled                                 = var.availability.http2_enabled
    websockets_enabled                            = var.availability.websockets_enabled
    use_32_bit_worker                             = false
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    ftps_state                                    = "Disabled"
    remote_debugging_enabled                      = false
    app_command_line                              = var.application.startup_command
    worker_count                                  = var.capacity.per_site_scaling_enabled ? var.capacity.app_worker_count : null
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    container_registry_use_managed_identity       = local.use_registry_managed_identity
    container_registry_managed_identity_client_id = local.is_container ? var.application.container.managed_identity_client_id : null
    vnet_route_all_enabled                        = local.vnet_integrated
    scm_use_main_ip_restriction                   = var.network.scm_use_main_ip_restriction
    ip_restriction_default_action                 = local.ip_restriction_default_action
    scm_ip_restriction_default_action             = local.scm_ip_restriction_default_action

    application_stack {
      docker_registry_url      = local.is_container ? var.application.container.registry_url : null
      docker_image_name        = local.production_docker_image
      docker_registry_username = local.is_container ? try(nonsensitive(var.container_registry_credentials.username), null) : null
      docker_registry_password = local.is_container ? try(var.container_registry_credentials.password, null) : null

      dotnet_version      = !local.is_container ? var.application.runtime.dotnet_version : null
      node_version        = !local.is_container ? var.application.runtime.node_version : null
      python_version      = !local.is_container ? var.application.runtime.python_version : null
      go_version          = !local.is_container ? var.application.runtime.go_version : null
      java_version        = !local.is_container ? var.application.runtime.java_version : null
      java_server         = !local.is_container && var.application.runtime.java_version != null ? var.application.runtime.java_server : null
      java_server_version = !local.is_container && var.application.runtime.java_version != null ? var.application.runtime.java_server_version : null
    }

    dynamic "auto_heal_setting" {
      for_each = var.health.auto_heal.enabled ? [1] : []

      content {
        trigger {
          status_code {
            status_code_range = var.health.auto_heal.status_code_trigger.status_code_range
            count             = var.health.auto_heal.status_code_trigger.count
            interval          = var.health.auto_heal.status_code_trigger.interval
          }

          dynamic "slow_request" {
            for_each = var.health.auto_heal.slow_request_trigger.enabled ? [1] : []

            content {
              time_taken = var.health.auto_heal.slow_request_trigger.time_taken
              count      = var.health.auto_heal.slow_request_trigger.count
              interval   = var.health.auto_heal.slow_request_trigger.interval
            }
          }
        }

        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = var.health.auto_heal.minimum_process_execution_time
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

        dynamic "headers" {
          for_each = ip_restriction.value.headers != null ? [ip_restriction.value.headers] : []

          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.network.scm_ip_restrictions

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
      for_each = var.network.cors != null ? [var.network.cors] : []

      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  sticky_settings {
    app_setting_names       = length(local.sticky_app_setting_names) > 0 ? local.sticky_app_setting_names : null
    connection_string_names = length(local.sticky_connection_string_names) > 0 ? local.sticky_connection_string_names : null
  }

  dynamic "connection_string" {
    for_each = local.connection_string_keys

    content {
      name  = connection_string.value
      type  = nonsensitive(var.connection_strings[connection_string.value].type)
      value = var.connection_strings[connection_string.value].value
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    dynamic "application_logs" {
      for_each = var.observability.application_log_level != "Off" ? [1] : []

      content {
        file_system_level = var.observability.application_log_level
      }
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.filesystem_http_log_retention_days
        retention_in_mb   = var.observability.filesystem_http_log_retention_mb
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Pre-Production Staging Slot (Safe Rollouts & Zero-Downtime Swaps)
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.rollout.staging_slot_enabled ? 1 : 0

  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = local.vnet_integrated
  key_vault_reference_identity_id                = var.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = var.rollout.basic_auth_publishing_enabled
  app_settings                                   = local.staging_app_settings
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = var.availability.always_on
    http2_enabled                                 = var.availability.http2_enabled
    websockets_enabled                            = var.availability.websockets_enabled
    use_32_bit_worker                             = false
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    ftps_state                                    = "Disabled"
    remote_debugging_enabled                      = false
    app_command_line                              = var.application.startup_command
    worker_count                                  = var.capacity.per_site_scaling_enabled ? var.capacity.app_worker_count : null
    auto_swap_slot_name                           = var.rollout.auto_swap_enabled ? "production" : null
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.eviction_time_in_min
    container_registry_use_managed_identity       = local.use_registry_managed_identity
    container_registry_managed_identity_client_id = local.is_container ? var.application.container.managed_identity_client_id : null
    vnet_route_all_enabled                        = local.vnet_integrated
    scm_use_main_ip_restriction                   = var.network.scm_use_main_ip_restriction
    ip_restriction_default_action                 = local.ip_restriction_default_action
    scm_ip_restriction_default_action             = local.scm_ip_restriction_default_action

    application_stack {
      docker_registry_url      = local.is_container ? var.application.container.registry_url : null
      docker_image_name        = local.staging_docker_image
      docker_registry_username = local.is_container ? try(nonsensitive(var.container_registry_credentials.username), null) : null
      docker_registry_password = local.is_container ? try(var.container_registry_credentials.password, null) : null

      dotnet_version      = !local.is_container ? var.application.runtime.dotnet_version : null
      node_version        = !local.is_container ? var.application.runtime.node_version : null
      python_version      = !local.is_container ? var.application.runtime.python_version : null
      go_version          = !local.is_container ? var.application.runtime.go_version : null
      java_version        = !local.is_container ? var.application.runtime.java_version : null
      java_server         = !local.is_container && var.application.runtime.java_version != null ? var.application.runtime.java_server : null
      java_server_version = !local.is_container && var.application.runtime.java_version != null ? var.application.runtime.java_server_version : null
    }

    dynamic "auto_heal_setting" {
      for_each = var.health.auto_heal.enabled ? [1] : []

      content {
        trigger {
          status_code {
            status_code_range = var.health.auto_heal.status_code_trigger.status_code_range
            count             = var.health.auto_heal.status_code_trigger.count
            interval          = var.health.auto_heal.status_code_trigger.interval
          }

          dynamic "slow_request" {
            for_each = var.health.auto_heal.slow_request_trigger.enabled ? [1] : []

            content {
              time_taken = var.health.auto_heal.slow_request_trigger.time_taken
              count      = var.health.auto_heal.slow_request_trigger.count
              interval   = var.health.auto_heal.slow_request_trigger.interval
            }
          }
        }

        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = var.health.auto_heal.minimum_process_execution_time
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

        dynamic "headers" {
          for_each = ip_restriction.value.headers != null ? [ip_restriction.value.headers] : []

          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.network.scm_ip_restrictions

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
      for_each = var.network.cors != null ? [var.network.cors] : []

      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  dynamic "connection_string" {
    for_each = local.connection_string_keys

    content {
      name  = connection_string.value
      type  = nonsensitive(var.connection_strings[connection_string.value].type)
      value = var.connection_strings[connection_string.value].value
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    dynamic "application_logs" {
      for_each = var.observability.application_log_level != "Off" ? [1] : []

      content {
        file_system_level = var.observability.application_log_level
      }
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.filesystem_http_log_retention_days
        retention_in_mb   = var.observability.filesystem_http_log_retention_mb
      }
    }
  }
}
