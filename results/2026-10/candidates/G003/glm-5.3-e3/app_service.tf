# ---------------------------------------------------------------------------
# Capacity: one dedicated Linux (container-capable) App Service plan per
# service, so capacity decisions are always per-service, never shared.
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "this" {
  name                   = "plan-${var.name}-${var.environment}"
  resource_group_name    = local.resource_group_name
  location               = local.location
  os_type                = "Linux"
  sku_name               = local.tier.sku
  worker_count           = local.effective_min_instances
  zone_balancing_enabled = local.zone_spreading
  tags                   = local.tags

  lifecycle {
    precondition {
      condition     = !(var.zone_redundant == true && !local.tier.zone_capable)
      error_message = "zone_redundant = true is not available on the '${var.tier}' tier (${local.tier.sku}); use 'medium' or above, or leave zone_redundant unset so the module picks a sensible default."
    }
  }
}

# ---------------------------------------------------------------------------
# The service itself: a Linux web app running the team's container.
# The module fixes every App Service internal (always-on, TLS floor, no FTP,
# HTTPS-only, health check) so SREs never hand-tune these per app.
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app" "this" {
  name                                           = local.web_app_name
  resource_group_name                            = local.resource_group_name
  location                                       = local.location
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    health_check_path                 = var.health_probe_path
    health_check_eviction_time_in_min = 5
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    websockets_enabled                = true
    minimum_tls_version               = "1.2"

    container_registry_use_managed_identity = local.container_registry_use_managed_identity

    application_stack {
      docker_image_name   = local.docker_image_name
      docker_registry_url = local.image_registry_url
    }
  }

  # Bounded local filesystem logging: keeps container stdout/stderr and HTTP
  # logs flowing into the AppServiceConsoleLogs/AppServiceHTTPLogs diagnostic
  # categories that are shipped to Log Analytics below.
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_mb   = 35
        retention_in_days = 7
      }
    }
  }

  app_settings = local.app_settings

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Rollouts: a warm staging slot, health-checked exactly like production, for
# blue/green deployment and verification before an explicit swap.
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app_slot" "staging" {
  count = var.create_staging_slot ? 1 : 0

  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    health_check_path                 = var.health_probe_path
    health_check_eviction_time_in_min = 5
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    websockets_enabled                = true
    minimum_tls_version               = "1.2"
    auto_swap_slot_name               = var.staging_auto_swap ? azurerm_linux_web_app.this.name : null

    container_registry_use_managed_identity = local.container_registry_use_managed_identity

    application_stack {
      docker_image_name   = local.docker_image_name
      docker_registry_url = local.image_registry_url
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_mb   = 35
        retention_in_days = 7
      }
    }
  }

  app_settings = local.app_settings

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Private registry support: grant the app's and the slot's identities pull
# access so nobody handles registry credentials by hand.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "acr_pull_app" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = var.container_registry_id != null && var.create_staging_slot ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
