resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_service_plan" "this" {
  count = local.create_service_plan ? 1 : 0

  name                   = "asp-${local.name_prefix}"
  resource_group_name    = local.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = local.sku_name
  worker_count           = var.capacity.min_instances
  zone_balancing_enabled = var.availability.zone_redundant
  tags                   = local.common_tags

  lifecycle {
    precondition {
      condition     = var.create_resource_group || var.resource_group_name != null
      error_message = "resource_group_name must be provided when create_resource_group is false."
    }
    precondition {
      condition     = !var.availability.zone_redundant || local.supports_zone_redundancy
      error_message = "availability.zone_redundant requires a Premium v2 or v3 SKU (e.g. P1v3, P2v3, P3v3, P1mv3)."
    }
    precondition {
      condition     = !var.availability.zone_redundant || var.capacity.min_instances >= 3
      error_message = "availability.zone_redundant requires capacity.min_instances >= 3 across availability zones."
    }
    precondition {
      condition     = !local.is_free_or_basic || var.capacity.max_instances == var.capacity.min_instances
      error_message = "Autoscaling (max_instances > min_instances) is not supported on Free or Basic SKUs (F1, D1, B1-B3)."
    }
  }

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_linux_web_app" "this" {
  name                                           = "app-${local.name_prefix}"
  resource_group_name                            = local.resource_group_name
  location                                       = var.location
  service_plan_id                                = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id
  https_only                                     = var.availability.https_only
  public_network_access_enabled                  = var.availability.public_network_access_enabled
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  virtual_network_subnet_id                      = var.availability.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.availability.vnet_integration_subnet_id != null
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(local.identity_ids) > 0 ? local.identity_ids : null
  }

  site_config {
    always_on                                     = local.always_on
    use_32_bit_worker                             = false
    http2_enabled                                 = var.availability.http2_enabled
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check.path
    health_check_eviction_time_in_min             = var.health_check.path != null ? var.health_check.eviction_time_minutes : null
    container_registry_use_managed_identity       = var.container_registry.use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry.use_managed_identity ? var.container_registry.managed_identity_client_id : null
    app_command_line                              = var.container_command
    vnet_route_all_enabled                        = var.availability.vnet_integration_subnet_id != null ? var.availability.vnet_route_all_enabled : false
    ip_restriction_default_action                 = var.availability.ip_restriction_default_action
    scm_use_main_ip_restriction                   = length(var.availability.ip_restrictions) > 0

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry.url
      docker_registry_username = var.container_registry.use_managed_identity ? null : var.container_registry.username
      docker_registry_password = var.container_registry.use_managed_identity ? null : var.container_registry_password
    }

    dynamic "cors" {
      for_each = var.availability.cors != null ? [var.availability.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = var.availability.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.observability.application_logs_level
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  app_settings = local.prod_app_settings

  dynamic "sticky_settings" {
    for_each = local.enable_staging_slot ? [1] : []
    content {
      app_setting_names = local.sticky_app_setting_names
    }
  }

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  lifecycle {
    precondition {
      condition     = !local.enable_staging_slot || local.supports_slots
      error_message = "Deployment slots (rollout.enable_staging_slot) require Standard (S1+) or Premium (P1v2+/P1v3+) SKUs."
    }
    precondition {
      condition     = var.create_resource_group || var.resource_group_name != null
      error_message = "resource_group_name must be provided when create_resource_group is false."
    }
  }

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = local.enable_staging_slot ? 1 : 0

  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = var.availability.https_only
  public_network_access_enabled                  = var.availability.public_network_access_enabled
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  virtual_network_subnet_id                      = var.availability.vnet_integration_subnet_id
  vnet_image_pull_enabled                        = var.availability.vnet_integration_subnet_id != null
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = merge(local.common_tags, { slot = "staging" })

  identity {
    type         = local.identity_type
    identity_ids = length(local.identity_ids) > 0 ? local.identity_ids : null
  }

  site_config {
    always_on                                     = local.always_on
    use_32_bit_worker                             = false
    http2_enabled                                 = var.availability.http2_enabled
    minimum_tls_version                           = var.availability.minimum_tls_version
    scm_minimum_tls_version                       = var.availability.minimum_tls_version
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check.path
    health_check_eviction_time_in_min             = var.health_check.path != null ? var.health_check.eviction_time_minutes : null
    container_registry_use_managed_identity       = var.container_registry.use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry.use_managed_identity ? var.container_registry.managed_identity_client_id : null
    app_command_line                              = var.container_command
    vnet_route_all_enabled                        = var.availability.vnet_integration_subnet_id != null ? var.availability.vnet_route_all_enabled : false
    ip_restriction_default_action                 = var.availability.ip_restriction_default_action
    scm_use_main_ip_restriction                   = length(var.availability.ip_restrictions) > 0

    application_stack {
      docker_image_name        = local.staging_container_image
      docker_registry_url      = var.container_registry.url
      docker_registry_username = var.container_registry.use_managed_identity ? null : var.container_registry.username
      docker_registry_password = var.container_registry.use_managed_identity ? null : var.container_registry_password
    }

    dynamic "cors" {
      for_each = var.availability.cors != null ? [var.availability.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = var.availability.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.observability.application_logs_level
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  app_settings = local.staging_app_settings

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }
}

resource "azurerm_role_assignment" "acr_pull_prod" {
  count = var.container_registry.use_managed_identity && var.container_registry.acr_id != null && var.container_registry.managed_identity_id == null ? 1 : 0

  scope                = var.container_registry.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = local.enable_staging_slot && var.container_registry.use_managed_identity && var.container_registry.acr_id != null && var.container_registry.managed_identity_id == null ? 1 : 0

  scope                = var.container_registry.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
