locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  # Managed identity registry auth when explicitly requested or when an ACR is
  # handed to us (the AcrPull assignment below makes it work end to end).
  registry_use_managed_identity = var.container_registry_use_managed_identity || var.acr_id != null

  # Opinionated baseline every standard service gets. Callers can override any
  # of these through var.app_settings.
  base_app_settings = merge(
    {
      # Wire the app to its Application Insights resource; the extension
      # version enables auto-instrumentation for supported runtimes.
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this.connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
      # Containers are immutable and stateless; don't mount the App Service
      # home share.
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    },
    var.container_port == null ? {} : { WEBSITES_PORT = tostring(var.container_port) },
  )

  app_settings = merge(local.base_app_settings, var.app_settings)
}

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# One dedicated plan per service: capacity is sized per service and a noisy
# neighbour can never take another service down.
resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  resource_group_name    = local.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.plan_sku
  zone_balancing_enabled = var.zone_redundant
  tags                   = var.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || can(regex("^[PI][0-9]m?v[23]$", var.plan_sku))
      error_message = "zone_redundant requires a Premium v2/v3 or Isolated v2 plan SKU (e.g. P0v3, P1v3)."
    }
    precondition {
      condition     = !var.zone_redundant || var.min_capacity >= 3
      error_message = "zone_redundant requires min_capacity >= 3 so instances can span three availability zones."
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                          = "app-${var.name}"
  resource_group_name           = local.resource_group_name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.this.id
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id
  client_affinity_enabled       = false # stateless HTTP APIs don't need ARR affinity
  tags                          = var.tags

  # Publishing endpoints authenticate with Entra ID only; pipelines hold
  # no passwords.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on               = true # required for health checks and slots
    http2_enabled           = true
    websockets_enabled      = false
    use_32_bit_worker       = false
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    ftps_state              = "Disabled" # deploy via pipelines, never FTP

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    container_registry_use_managed_identity = local.registry_use_managed_identity
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }

    # Self-healing: recycle a worker that keeps serving 5xx instead of waiting
    # for a human to notice.
    auto_heal_setting {
      action {
        action_type = "Recycle"
      }
      trigger {
        status_code {
          status_code_range = "500"
          count             = var.auto_heal_5xx_count
          interval          = var.auto_heal_time_interval
        }
      }
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
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  app_settings = local.app_settings

  dynamic "sticky_settings" {
    for_each = length(var.slot_sticky_app_settings) > 0 ? [var.slot_sticky_app_settings] : []
    content {
      app_setting_names = sticky_settings.value
    }
  }
}

# Standard rollout target: deploy the new image here, warm it up behind the
# health check, then swap it into production from the CD pipeline.
resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name                          = "staging"
  app_service_id                = azurerm_linux_web_app.this.id
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id
  client_affinity_enabled       = false
  tags                          = var.tags

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on               = true
    http2_enabled           = true
    websockets_enabled      = false
    use_32_bit_worker       = false
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    ftps_state              = "Disabled"

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    container_registry_use_managed_identity = local.registry_use_managed_identity
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }

    auto_heal_setting {
      action {
        action_type = "Recycle"
      }
      trigger {
        status_code {
          status_code_range = "500"
          count             = var.auto_heal_5xx_count
          interval          = var.auto_heal_time_interval
        }
      }
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
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  app_settings = local.app_settings
}

# Pull-from-ACR without credentials anywhere in state or config.
resource "azurerm_role_assignment" "app_acr_pull" {
  count = var.acr_id == null ? 0 : 1

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_acr_pull" {
  count = var.acr_id != null && var.enable_staging_slot ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
