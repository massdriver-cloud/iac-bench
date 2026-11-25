# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name

  lifecycle {
    precondition {
      condition     = var.resource_group_name != null
      error_message = "resource_group_name must be provided when create_resource_group is false."
    }
  }
}

locals {
  rg_name     = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  rg_location = var.location
}

# ------------------------------------------------------------------------------
# Linux App Service Plan (Compute & Availability)
# ------------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count = local.create_service_plan ? 1 : 0

  name                   = local.service_plan_name
  resource_group_name    = local.rg_name
  location               = local.rg_location
  os_type                = "Linux"
  sku_name               = local.sku_name
  worker_count           = local.effective_default_instances
  zone_balancing_enabled = var.availability.zone_redundant
  tags                   = local.common_tags

  lifecycle {
    # Live worker count is actively managed by Azure Monitor Autoscale;
    # ignoring drift prevents routine applies from scaling down under load.
    ignore_changes = [worker_count]

    precondition {
      condition     = !var.availability.zone_redundant || local.supports_zone_redundancy
      error_message = "availability.zone_redundant requires a Premium v2/v3 or Isolated v2 SKU (e.g. P0v3, P1v3, P2v3, P3v3). Resolved SKU: ${local.sku_name}."
    }

    precondition {
      condition     = !var.rollout.staging_slot_enabled || local.supports_slots
      error_message = "rollout.staging_slot_enabled requires a Standard, Premium, or Isolated SKU. Resolved SKU: ${local.sku_name}."
    }

    precondition {
      condition     = !var.capacity.autoscale_enabled || local.supports_autoscale
      error_message = "capacity.autoscale_enabled requires a Standard, Premium, or Isolated SKU. Resolved SKU: ${local.sku_name}."
    }

    precondition {
      condition     = var.networking.private_endpoint_subnet_id == null || local.supports_private_endpoint
      error_message = "networking.private_endpoint_subnet_id requires a Premium v2/v3 or Isolated SKU. Resolved SKU: ${local.sku_name}."
    }
  }
}

locals {
  service_plan_id = local.create_service_plan ? azurerm_service_plan.this[0].id : var.existing_service_plan_id
}

# ------------------------------------------------------------------------------
# Linux Web App (Containerized HTTP API)
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = local.web_app_name
  resource_group_name = local.rg_name
  location            = local.rg_location
  service_plan_id     = local.service_plan_id

  https_only                                     = true
  client_affinity_enabled                        = var.availability.client_affinity_enabled
  public_network_access_enabled                  = var.networking.public_network_access_enabled
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.networking.vnet_subnet_id
  vnet_image_pull_enabled                        = var.container.vnet_image_pull_enabled

  app_settings = local.prod_app_settings
  tags         = local.common_tags

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  site_config {
    always_on                                     = local.effective_always_on
    use_32_bit_worker                             = local.use_32_bit_worker
    ftps_state                                    = "Disabled"
    http2_enabled                                 = var.networking.http2_enabled
    websockets_enabled                            = var.networking.websockets_enabled
    minimum_tls_version                           = var.networking.minimum_tls_version
    scm_minimum_tls_version                       = var.networking.minimum_tls_version
    load_balancing_mode                           = var.availability.load_balancing_mode
    health_check_path                             = var.health.path
    health_check_eviction_time_in_min             = var.health.path != null ? var.health.eviction_time_in_min : null
    app_command_line                              = var.container.start_command
    container_registry_use_managed_identity       = local.use_acr_managed_identity
    container_registry_managed_identity_client_id = local.use_acr_managed_identity ? var.container.acr_managed_identity_client_id : null
    vnet_route_all_enabled                        = var.networking.vnet_subnet_id != null ? var.networking.vnet_route_all_enabled : false
    ip_restriction_default_action                 = var.networking.ip_restriction_default_action
    scm_use_main_ip_restriction                   = var.networking.scm_use_main_ip_restriction
    scm_ip_restriction_default_action             = var.networking.scm_ip_restriction_default_action

    application_stack {
      docker_image_name        = local.prod_docker_image_name
      docker_registry_url      = local.prod_registry_url
      docker_registry_username = local.use_acr_managed_identity ? null : var.container.registry_username
      docker_registry_password = local.use_acr_managed_identity ? null : var.container_registry_password
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

    dynamic "scm_ip_restriction" {
      for_each = var.networking.scm_ip_restrictions
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
      for_each = var.networking.cors != null ? [var.networking.cors] : []
      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = var.rollout.staging_slot_enabled ? [1] : []
    content {
      app_setting_names = local.sticky_app_setting_names
    }
  }

  logs {
    detailed_error_messages = var.observability.detailed_error_messages
    failed_request_tracing  = var.observability.failed_request_tracing

    application_logs {
      file_system_level = var.observability.application_log_level
    }

    http_logs {
      file_system {
        retention_in_days = var.observability.http_logs_retention_days
        retention_in_mb   = 35
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Optional ACR Pull RBAC for Production App Managed Identity
# ------------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull_prod" {
  count = var.container.acr_id != null ? 1 : 0

  scope                = var.container.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}
