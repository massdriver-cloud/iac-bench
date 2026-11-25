# =====================================================================================================================
# Rollouts: Staging Deployment Slot for Zero-Downtime Deployments & Warm-up
# =====================================================================================================================

resource "azurerm_linux_web_app_slot" "staging" {
  count                     = var.enable_staging_slot ? 1 : 0
  name                      = "staging"
  app_service_id            = azurerm_linux_web_app.this.id
  https_only                = true
  client_affinity_enabled   = false
  virtual_network_subnet_id = var.virtual_network_subnet_id
  tags                      = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    http2_enabled                           = true
    vnet_route_all_enabled                  = var.virtual_network_subnet_id != null ? true : false
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }

    auto_heal_enabled = var.auto_heal_enabled

    dynamic "auto_heal_setting" {
      for_each = var.auto_heal_enabled ? [1] : []
      content {
        action {
          action_type = "Recycle"
        }
        trigger {
          status_code {
            status_code_range = "500-599"
            count             = var.auto_heal_5xx_count
            interval          = var.auto_heal_time_interval
          }
        }
      }
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_cidrs
      content {
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = 100 + index(var.allowed_ip_cidrs, ip_restriction.value) * 10
        name       = "Allow-${replace(ip_restriction.value, "/[^a-zA-Z0-9]/", "-")}"
      }
    }
  }

  app_settings = local.staging_app_settings

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name
    ]
  }
}
