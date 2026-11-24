resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_service_plan" "this" {
  count = local.create_service_plan ? 1 : 0

  name                     = "asp-${local.name_prefix}"
  resource_group_name      = local.resource_group_name
  location                 = var.location
  os_type                  = "Linux"
  sku_name                 = local.sku_name
  worker_count             = local.zone_balancing_enabled ? max(3, var.capacity.min_instances) : var.capacity.min_instances
  per_site_scaling_enabled = var.capacity.per_site_scaling
  zone_balancing_enabled   = local.zone_balancing_enabled
  tags                     = local.common_tags

  lifecycle {
    precondition {
      condition     = !var.availability.zone_redundant || local.supports_zone_balancing
      error_message = "availability.zone_redundant requires a Premium SKU (size 'small', 'medium', 'large', 'xlarge', or P*v2/P*v3 sku_name)."
    }

    precondition {
      condition     = !var.availability.zone_redundant || var.capacity.min_instances >= 3
      error_message = "availability.zone_redundant requires capacity.min_instances >= 3 for 3-zone App Service balancing."
    }

    ignore_changes = [
      # Allow Azure Monitor Autoscale to adjust worker_count dynamically without Terraform reverting it.
      worker_count,
    ]
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                           = "app-${local.name_prefix}"
  resource_group_name                            = local.resource_group_name
  location                                       = var.location
  service_plan_id                                = local.service_plan_id
  https_only                                     = true
  public_network_access_enabled                  = var.availability.public_network_access_enabled
  virtual_network_subnet_id                      = var.availability.vnet_subnet_id
  vnet_image_pull_enabled                        = var.availability.vnet_image_pull_enabled
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = local.always_on_enabled
    use_32_bit_worker                             = false
    http2_enabled                                 = true
    minimum_tls_version                           = var.minimum_tls_version
    ftps_state                                    = "Disabled"
    vnet_route_all_enabled                        = var.availability.vnet_subnet_id != null ? var.availability.vnet_route_all_enabled : false
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.path != null ? var.health.eviction_time_in_min : null
    load_balancing_mode                           = var.availability.load_balancing_mode
    app_command_line                              = var.container.startup_command
    container_registry_use_managed_identity       = local.use_managed_identity_for_registry
    container_registry_managed_identity_client_id = var.container.managed_identity_client_id
    ip_restriction_default_action                 = var.availability.ip_restriction_default_action
    scm_use_main_ip_restriction                   = local.scm_use_main_ip_restriction

    application_stack {
      docker_registry_url      = local.docker_registry_url
      docker_image_name        = local.docker_image_name
      docker_registry_username = local.use_managed_identity_for_registry ? null : var.container.registry_username
      docker_registry_password = local.use_managed_identity_for_registry ? null : var.container.registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.availability.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        ip_address                = ip_restriction.value.ip_address
        virtual_network_subnet_id = ip_restriction.value.subnet_id
        service_tag               = ip_restriction.value.service_tag
      }
    }

    dynamic "cors" {
      for_each = var.cors != null ? [var.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  app_settings = local.base_app_settings

  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }

    application_logs {
      file_system_level = var.observability.application_log_level
    }
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container.acr_id != null ? 1 : 0

  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}
