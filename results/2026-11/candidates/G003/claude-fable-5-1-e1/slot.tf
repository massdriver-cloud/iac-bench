############################################
# Staging deployment slot (swap-based rollouts)
#
# The slot mirrors the production configuration and image. Typical flow:
#   1. bump container_image, apply  -> both slots get the new image
#      (or deploy to the slot out-of-band via your CD system)
#   2. warm-up / verify on <name>-staging.azurewebsites.net
#   3. `az webapp deployment slot swap` -> zero-downtime cutover
# Sticky settings (sticky_settings on the production app) stay with their slot.
############################################

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only                    = true
  client_affinity_enabled       = false
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_acr_identity
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null
    ip_restriction_default_action           = local.restrict_inbound ? "Deny" : "Allow"
    scm_ip_restriction_default_action       = local.restrict_inbound ? "Deny" : "Allow"
    load_balancing_mode                     = "LeastRequests"

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.ip_address
        action     = "Allow"
        priority   = ip_restriction.value.priority
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = scm_ip_restriction.value.name
        ip_address = scm_ip_restriction.value.ip_address
        action     = "Allow"
        priority   = scm_ip_restriction.value.priority
      }
    }
  }

  app_settings = local.app_settings

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  tags = local.tags

  depends_on = [terraform_data.sku_guard]
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = local.use_acr_identity && var.enable_staging_slot ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name                       = "${var.name}-staging-diag"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.web_app_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
