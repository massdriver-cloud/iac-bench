# =============================================================================
# The service: a Linux web app running a container
# =============================================================================

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  tags                = local.tags

  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  # System-assigned identity: used for ACR pulls and available for Key Vault
  # references in app settings.
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true

    # Health: instances failing this probe are pulled from the load balancer
    # and restarted after the eviction window.
    health_check_path                 = local.health_check_path
    health_check_eviction_time_in_min = local.health_check_path != null ? 10 : null

    http2_enabled            = true
    minimum_tls_version      = "1.2"
    ftps_state               = "Disabled"
    remote_debugging_enabled = false

    # Route all outbound traffic through the VNet when integrated with one.
    vnet_route_all_enabled = var.vnet_integration_subnet_id != null

    # With an allow-list in place, everything else is denied.
    ip_restriction_default_action = length(var.allowed_ip_address_ranges) > 0 ? "Deny" : "Allow"

    container_registry_use_managed_identity = local.use_acr_managed_identity

    # The container the service runs. docker_image_name is the full image
    # reference (registry host + repository + tag); registry credentials are
    # basic-auth only - for Azure Container Registry the managed identity
    # above is used instead.
    application_stack {
      docker_image_name         = local.docker_image_name
      docker_registry_url       = var.container_registry_url
      docker_registry_username  = var.container_registry_username
      docker_registry_password  = var.container_registry_password
    }

    # Self-healing: recycle a worker that keeps returning 5xx before the
    # health check has to evict the whole instance.
    auto_heal_setting {
      trigger {
        status_code {
          status_code_range = "500-599"
          count             = 20
          interval          = "00:02:00"
        }
      }

      action {
        action_type = "Recycle"
      }
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = false
      }
    }

    dynamic "ip_restriction" {
      for_each = toset(var.allowed_ip_address_ranges)
      content {
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = index(var.allowed_ip_address_ranges, ip_restriction.value) + 100
      }
    }
  }

  app_settings = local.app_settings

  # Settings listed here stay with the slot during swaps.
  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_settings) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_settings
    }
  }

  lifecycle {
    precondition {
      condition     = (var.container_registry_username == null) == (var.container_registry_password == null)
      error_message = "container_registry_username and container_registry_password must be provided together."
    }

    precondition {
      condition     = var.container_registry_id == null || (var.container_registry_username == null && var.container_registry_url == null)
      error_message = "Use either container_registry_id (Azure Container Registry with managed identity) or basic-auth credentials, not both."
    }

    precondition {
      condition     = var.container_registry_username == null || var.container_registry_url != null
      error_message = "container_registry_url is required when using container_registry_username/container_registry_password."
    }

    precondition {
      condition     = !var.enable_auto_swap || var.enable_staging_slot
      error_message = "enable_auto_swap requires enable_staging_slot."
    }
  }
}

# =============================================================================
# Rollout: the staging slot for blue/green deployments
#
# The slot mirrors production (same image pin, health check, TLS policy,
# identity, network configuration) so a swap is safe. CI deploys new versions
# to this slot, waits for it to become healthy, and swaps it into production.
# =============================================================================

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name            = "staging"
  app_service_id  = azurerm_linux_web_app.this.id
  service_plan_id = azurerm_service_plan.this.id
  https_only      = true
  tags            = local.tags

  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    health_check_path                 = local.health_check_path
    health_check_eviction_time_in_min = local.health_check_path != null ? 10 : null
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    remote_debugging_enabled          = false
    vnet_route_all_enabled            = var.vnet_integration_subnet_id != null
    ip_restriction_default_action     = length(var.allowed_ip_address_ranges) > 0 ? "Deny" : "Allow"

    container_registry_use_managed_identity = local.use_acr_managed_identity

    # Optional CI convenience: swap into production automatically once the
    # slot is warm.
    auto_swap_slot_name = var.enable_auto_swap ? "production" : null

    application_stack {
      docker_image_name        = local.docker_image_name
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    auto_heal_setting {
      trigger {
        status_code {
          status_code_range = "500-599"
          count             = 20
          interval          = "00:02:00"
        }
      }

      action {
        action_type = "Recycle"
      }
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = false
      }
    }

    dynamic "ip_restriction" {
      for_each = toset(var.allowed_ip_address_ranges)
      content {
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = index(var.allowed_ip_address_ranges, ip_restriction.value) + 100
      }
    }
  }

  app_settings = local.app_settings
}

# =============================================================================
# Registry access: AcrPull for the app and the staging slot when pulling from
# a private Azure Container Registry with their managed identities.
#
# Note: on first deployment App Service may retry the image pull for a few
# minutes until the role assignment has propagated. This is expected.
# =============================================================================

resource "azurerm_role_assignment" "acrpull" {
  for_each = var.container_registry_id != null ? local.acr_pull_principals : {}

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = each.value
}
