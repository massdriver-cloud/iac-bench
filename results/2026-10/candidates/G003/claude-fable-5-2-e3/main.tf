resource "random_string" "suffix" {
  length  = 5
  lower   = true
  numeric = true
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "rg-${local.base_name}"
  location = var.location
  tags     = local.tags
}

###############################################################################
# Identity
#
# One user-assigned identity per service, shared by production and staging.
# It pulls the image, resolves Key Vault references, and is what SREs grant
# access to when the service needs a database, queue, etc.
###############################################################################

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${local.base_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  for_each = toset(var.key_vault_ids)

  scope                = each.value
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

###############################################################################
# Compute: a dedicated Linux Premium v3 plan per service
###############################################################################

resource "azurerm_service_plan" "this" {
  name                = "asp-${local.base_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  # Initial size only: from then on the autoscale setting owns the instance
  # count (see autoscale.tf), also for fixed-size services (min == max).
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant

  tags = local.tags

  lifecycle {
    ignore_changes = [worker_count]

    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances (${var.max_instances}) must be greater than or equal to min_instances (${var.min_instances})."
    }

    precondition {
      condition     = !var.zone_redundant || var.min_instances >= 2
      error_message = "A zone-redundant service needs at least 2 instances: raise min_instances to 2 or more, or set zone_redundant = false (acceptable for non-production only)."
    }
  }
}

###############################################################################
# Production app
###############################################################################

resource "azurerm_linux_web_app" "this" {
  name                = local.app_name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  client_affinity_enabled       = var.session_affinity_enabled
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.integration_subnet_id
  vnet_image_pull_enabled       = var.integration_subnet_id != null

  # No shared-secret deployment credentials: images come from the registry,
  # configuration comes from this module.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  key_vault_reference_identity_id = azurerm_user_assigned_identity.this.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.app_settings

  site_config {
    always_on           = true
    http2_enabled       = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    container_registry_use_managed_identity       = local.images.production.use_managed_identity
    container_registry_managed_identity_client_id = local.images.production.use_managed_identity ? azurerm_user_assigned_identity.this.client_id : null

    vnet_route_all_enabled = var.integration_subnet_id != null

    ip_restriction_default_action     = local.ip_restriction_default_action
    scm_use_main_ip_restriction       = true
    scm_minimum_tls_version           = "1.2"
    scm_ip_restriction_default_action = local.ip_restriction_default_action

    application_stack {
      docker_registry_url = local.images.production.registry_url
      docker_image_name   = local.images.production.name
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions

      content {
        name        = ip_restriction.value.name
        action      = "Allow"
        priority    = ip_restriction.value.priority
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag

        dynamic "headers" {
          for_each = ip_restriction.value.front_door_id[*]

          content {
            x_azure_fdid = [headers.value]
          }
        }
      }
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []

      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = false
      }
    }
  }

  # Short-lived on-instance logs for live log streaming; the durable copy goes
  # to Log Analytics through the diagnostic setting.
  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = length(local.sticky_app_setting_names) > 0 ? [1] : []

    content {
      app_setting_names = local.sticky_app_setting_names
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(setintersection(keys(var.app_settings), keys(var.key_vault_secrets))) == 0
      error_message = "The same variable name is set in both app_settings and key_vault_secrets: ${join(", ", setintersection(keys(var.app_settings), keys(var.key_vault_secrets)))}."
    }

    precondition {
      condition     = var.staging_slot_enabled || (var.staging_image == null && length(var.staging_app_settings) == 0)
      error_message = "staging_image and staging_app_settings only apply when staging_slot_enabled is true."
    }
  }

  # The identity must be able to pull the image and read secrets before the
  # first container start.
  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets_user,
  ]
}

###############################################################################
# Staging slot (blue/green rollouts)
#
# Same hardening, identity, health check and network rules as production; only
# the image and the sticky staging_app_settings may differ.
###############################################################################

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = local.slot_name
  app_service_id = azurerm_linux_web_app.this.id

  https_only                    = true
  client_affinity_enabled       = var.session_affinity_enabled
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.integration_subnet_id
  vnet_image_pull_enabled       = var.integration_subnet_id != null

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  key_vault_reference_identity_id = azurerm_user_assigned_identity.this.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.staging_app_settings

  site_config {
    always_on           = true
    http2_enabled       = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    container_registry_use_managed_identity       = local.images.staging.use_managed_identity
    container_registry_managed_identity_client_id = local.images.staging.use_managed_identity ? azurerm_user_assigned_identity.this.client_id : null

    vnet_route_all_enabled = var.integration_subnet_id != null

    ip_restriction_default_action     = local.ip_restriction_default_action
    scm_use_main_ip_restriction       = true
    scm_minimum_tls_version           = "1.2"
    scm_ip_restriction_default_action = local.ip_restriction_default_action

    application_stack {
      docker_registry_url = local.images.staging.registry_url
      docker_image_name   = local.images.staging.name
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions

      content {
        name        = ip_restriction.value.name
        action      = "Allow"
        priority    = ip_restriction.value.priority
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag

        dynamic "headers" {
          for_each = ip_restriction.value.front_door_id[*]

          content {
            x_azure_fdid = [headers.value]
          }
        }
      }
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []

      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = false
      }
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  tags = local.tags
}
