# -----------------------------------------------------------------------------
# The web app: a Linux App Service running the team's container image.
#
# Hardened defaults the SRE team should not have to think about per app:
# Always On, HTTPS-only, TLS 1.2, FTP/webdeploy basic auth and FTPS disabled,
# HTTP/2, no session affinity, health check eviction of unhealthy instances.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.virtual_network_subnet_id
  tags                                           = local.tags

  app_settings = local.app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_minutes
    websockets_enabled                = var.websockets_enabled

    container_registry_use_managed_identity = local.registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = local.registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = local.auto_heal_policy
      content {
        trigger {
          status_code {
            status_code_range = auto_heal_setting.value.status_code_range
            count             = auto_heal_setting.value.status_code_count
            interval          = format("00:%02d:00", auto_heal_setting.value.interval_minutes)
          }
          slow_request {
            count      = auto_heal_setting.value.slow_request_count
            interval   = format("00:%02d:00", auto_heal_setting.value.interval_minutes)
            time_taken = format("00:%02d:%02d", floor(auto_heal_setting.value.slow_request_seconds / 60), auto_heal_setting.value.slow_request_seconds % 60)
          }
        }
        action {
          action_type = "Recycle"
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = (var.container_registry_username == null) == (var.container_registry_password == null)
      error_message = "container_registry_username and container_registry_password must be set together."
    }

    precondition {
      condition     = var.acr_resource_id == null || (var.container_registry_username == null && var.container_registry_password == null)
      error_message = "Use either acr_resource_id (managed identity pull) or container_registry_username/container_registry_password (basic auth), not both."
    }

    precondition {
      condition     = var.staging_container_image == null || var.enable_staging_slot
      error_message = "staging_container_image requires enable_staging_slot = true."
    }
  }
}

# -----------------------------------------------------------------------------
# Staging slot: a mirror of production used to verify a candidate image before
# promotion. It shares the plan's instances, so it costs memory, not VMs.
# Health checks are identical so a rollout never promotes an unhealthy build.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name            = var.staging_slot_name
  app_service_id  = azurerm_linux_web_app.this.id
  service_plan_id = azurerm_service_plan.this.id

  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.virtual_network_subnet_id
  tags                                           = local.tags

  app_settings = local.app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_minutes
    websockets_enabled                = var.websockets_enabled

    container_registry_use_managed_identity = local.registry_use_managed_identity

    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = local.registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "auto_heal_setting" {
      for_each = local.auto_heal_policy
      content {
        trigger {
          status_code {
            status_code_range = auto_heal_setting.value.status_code_range
            count             = auto_heal_setting.value.status_code_count
            interval          = format("00:%02d:00", auto_heal_setting.value.interval_minutes)
          }
          slow_request {
            count      = auto_heal_setting.value.slow_request_count
            interval   = format("00:%02d:00", auto_heal_setting.value.interval_minutes)
            time_taken = format("00:%02d:%02d", floor(auto_heal_setting.value.slow_request_seconds / 60), auto_heal_setting.value.slow_request_seconds % 60)
          }
        }
        action {
          action_type = "Recycle"
        }
      }
    }
  }
}
