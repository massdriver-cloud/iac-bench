# ---------------------------------------------------------------------------
# The Linux Web App and its staging slot.
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = "app-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = var.always_on
    http2_enabled                           = local.env.http2
    minimum_tls_version                     = local.env.min_tls_version
    ftps_state                              = local.env.ftps_state
    health_check_path                       = var.health_check_path == "" ? null : var.health_check_path
    health_check_eviction_time_in_min       = 10
    container_registry_use_managed_identity = var.registry.use_managed_identity
    vnet_route_all_enabled                  = false
    use_32_bit_worker                       = false
    websockets_enabled                      = true

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        priority   = ip_restriction.value.priority
        ip_address = ip_restriction.value.ip_address
        action     = ip_restriction.value.action
      }
    }

    application_stack {
      docker_image_name   = var.image
      docker_registry_url = "https://${var.registry.server_url}"
    }
  }

  app_settings = local.app_settings_computed

  lifecycle {
    ignore_changes = [
      app_settings["DOCKER_REGISTRY_SERVER_PASSWORD"],
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.slot_enabled ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = false
    http2_enabled                           = local.env.http2
    minimum_tls_version                     = local.env.min_tls_version
    ftps_state                              = local.env.ftps_state
    container_registry_use_managed_identity = var.registry.use_managed_identity
    use_32_bit_worker                       = false
    websockets_enabled                      = true

    application_stack {
      docker_image_name   = var.image
      docker_registry_url = "https://${var.registry.server_url}"
    }
  }

  app_settings = merge(
    local.app_settings_computed,
    {
      DEPLOYMENT_SLOT                   = "staging"
      WEBSITE_SWAP_WARMUP_PING_PATH     = var.health_check_path == "" ? "/" : var.health_check_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES = "200,202"
    }
  )

  lifecycle {
    ignore_changes = [
      app_settings["DOCKER_REGISTRY_SERVER_PASSWORD"],
    ]
  }
}