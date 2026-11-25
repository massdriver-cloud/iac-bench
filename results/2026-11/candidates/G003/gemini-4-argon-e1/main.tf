locals {
  name_prefix = "${var.name}-${var.environment}"
  rg_name     = coalesce(var.resource_group_name, "rg-${local.name_prefix}")
  location    = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location

  # Zone balancing on App Service Plans requires Premium v2/v3/mv3 SKUs and at least 3 instances in Azure
  supports_zone_redundancy = contains(["P1v2", "P2v2", "P3v2", "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.capacity.sku_name)
  zone_balancing_enabled   = var.availability.zone_balancing_enabled && local.supports_zone_redundancy && var.capacity.min_instances >= 3

  production_image = var.container.image
  staging_image    = coalesce(var.rollout.staging_image_override, var.container.image)

  identity_type = length(var.identity.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  log_analytics_workspace_id = coalesce(
    var.observability.log_analytics_workspace_id,
    try(azurerm_log_analytics_workspace.this[0].id, null)
  )

  # Base runtime environment settings automatically managed by the module
  base_app_settings = merge(
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE             = "false"
      WEBSITES_PORT                                   = tostring(var.container.port)
      DOCKER_ENABLE_CI                                = "false"
      WEBSITE_ADD_SITENAME_BINDINGS_IN_APPHOST_CONFIG = "1"
    },
    var.rollout.warm_up_init_path != null ? {
      WEBSITE_SWAP_WARMUP_PING_PATH     = var.rollout.warm_up_init_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES = var.rollout.warm_up_status_codes
    } : {},
    var.observability.application_insights_enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
      APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.this[0].instrumentation_key
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
      XDT_MicrosoftApplicationInsights_Mode      = "recommended"
    } : {}
  )

  production_app_settings = merge(
    local.base_app_settings,
    var.app_settings,
    {
      SERVICE_ENVIRONMENT = var.environment
      DEPLOYMENT_SLOT     = "production"
    }
  )

  staging_app_settings = merge(
    local.base_app_settings,
    var.app_settings,
    var.rollout.staging_app_settings,
    {
      SERVICE_ENVIRONMENT = var.environment
      DEPLOYMENT_SLOT     = "staging"
    }
  )

  sticky_app_setting_names = distinct(concat(
    ["DEPLOYMENT_SLOT"],
    var.sticky_app_settings
  ))

  action_group_ids = distinct(concat(
    var.observability.action_group_ids,
    length(azurerm_monitor_action_group.this) > 0 ? [azurerm_monitor_action_group.this[0].id] : []
  ))

  common_tags = merge(
    {
      "service"     = var.name
      "environment" = var.environment
      "managed-by"  = "opentofu"
    },
    var.tags
  )
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_service_plan" "this" {
  name                         = "asp-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name          = local.rg_name
  location                     = local.location
  os_type                      = "Linux"
  sku_name                     = var.capacity.sku_name
  worker_count                 = var.capacity.default_instances
  zone_balancing_enabled       = local.zone_balancing_enabled
  per_site_scaling_enabled     = false
  maximum_elastic_worker_count = null
  tags                         = local.common_tags

  lifecycle {
    ignore_changes = [
      # Ignored when autoscale dynamically adjusts instance count
      worker_count
    ]
  }

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_linux_web_app" "this" {
  name                                           = "app-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name                            = local.rg_name
  location                                       = local.location
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  client_certificate_enabled                     = var.network.client_certificate_enabled
  client_certificate_mode                        = var.network.client_certificate_mode
  key_vault_reference_identity_id                = var.identity.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.production_app_settings
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.identity.user_assigned_identity_ids) > 0 ? var.identity.user_assigned_identity_ids : null
  }

  site_config {
    always_on                               = var.availability.always_on
    http2_enabled                           = var.availability.http2_enabled
    minimum_tls_version                     = var.network.minimum_tls_version
    scm_minimum_tls_version                 = var.network.minimum_tls_version
    ftps_state                              = "Disabled"
    health_check_path                       = var.health.path
    health_check_eviction_time_in_min       = var.health.eviction_time_in_min
    vnet_route_all_enabled                  = var.network.vnet_integration_subnet_id != null ? var.network.vnet_route_all_enabled : false
    container_registry_use_managed_identity = var.container.registry_use_managed_identity
    app_command_line                        = var.container.startup_command
    scm_use_main_ip_restriction             = var.network.scm_use_main_ip_restriction

    application_stack {
      docker_image_name        = local.production_image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = var.availability.auto_heal_enabled ? [1] : []
      content {
        action {
          action_type = "Recycle"
        }
        trigger {
          status_code {
            status_code_range = var.availability.auto_heal_status_codes.status_code_range
            count             = var.availability.auto_heal_status_codes.count
            interval          = var.availability.auto_heal_status_codes.interval
          }
          slow_request {
            time_taken = var.availability.auto_heal_slow_requests.time_taken
            count      = var.availability.auto_heal_slow_requests.count
            interval   = var.availability.auto_heal_slow_requests.interval
          }
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
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        service_tag               = ip_restriction.value.service_tag
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
    detailed_error_messages = var.observability.detailed_error_messages
    failed_request_tracing  = var.observability.failed_request_tracing

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = var.observability.http_logs_retention_mb
      }
    }
  }

  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }

  dynamic "connection_string" {
    for_each = nonsensitive(var.connection_strings)
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = sensitive(connection_string.value.value)
    }
  }

  dynamic "storage_account" {
    for_each = var.container.mount_storage
    content {
      name         = storage_account.value.name
      account_name = storage_account.value.account_name
      share_name   = storage_account.value.share_name
      access_key   = storage_account.value.access_key
      mount_path   = storage_account.value.mount_path
      type         = storage_account.value.type
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.rollout.staging_slot_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.network.public_network_access_enabled
  virtual_network_subnet_id                      = var.network.vnet_integration_subnet_id
  client_certificate_enabled                     = var.network.client_certificate_enabled
  client_certificate_mode                        = var.network.client_certificate_mode
  key_vault_reference_identity_id                = var.identity.key_vault_reference_identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.staging_app_settings
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.identity.user_assigned_identity_ids) > 0 ? var.identity.user_assigned_identity_ids : null
  }

  site_config {
    always_on                               = var.availability.always_on
    http2_enabled                           = var.availability.http2_enabled
    minimum_tls_version                     = var.network.minimum_tls_version
    scm_minimum_tls_version                 = var.network.minimum_tls_version
    ftps_state                              = "Disabled"
    health_check_path                       = var.health.path
    health_check_eviction_time_in_min       = var.health.eviction_time_in_min
    vnet_route_all_enabled                  = var.network.vnet_integration_subnet_id != null ? var.network.vnet_route_all_enabled : false
    container_registry_use_managed_identity = var.container.registry_use_managed_identity
    app_command_line                        = var.container.startup_command
    scm_use_main_ip_restriction             = var.network.scm_use_main_ip_restriction
    auto_swap_slot_name                     = var.rollout.auto_swap_enabled ? "production" : null

    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = var.container.registry_url
      docker_registry_username = var.container.registry_username
      docker_registry_password = var.container.registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = var.availability.auto_heal_enabled ? [1] : []
      content {
        action {
          action_type = "Recycle"
        }
        trigger {
          status_code {
            status_code_range = var.availability.auto_heal_status_codes.status_code_range
            count             = var.availability.auto_heal_status_codes.count
            interval          = var.availability.auto_heal_status_codes.interval
          }
          slow_request {
            time_taken = var.availability.auto_heal_slow_requests.time_taken
            count      = var.availability.auto_heal_slow_requests.count
            interval   = var.availability.auto_heal_slow_requests.interval
          }
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
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        service_tag               = ip_restriction.value.service_tag
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
    detailed_error_messages = var.observability.detailed_error_messages
    failed_request_tracing  = var.observability.failed_request_tracing

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = var.observability.http_logs_retention_mb
      }
    }
  }

  dynamic "connection_string" {
    for_each = nonsensitive(var.connection_strings)
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = sensitive(connection_string.value.value)
    }
  }

  dynamic "storage_account" {
    for_each = var.container.mount_storage
    content {
      name         = storage_account.value.name
      account_name = storage_account.value.account_name
      share_name   = storage_account.value.share_name
      access_key   = storage_account.value.access_key
      mount_path   = storage_account.value.mount_path
      type         = storage_account.value.type
    }
  }
}
