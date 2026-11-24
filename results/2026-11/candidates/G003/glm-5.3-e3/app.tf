# -----------------------------------------------------------------------------
# The service: a Linux web app running the team's container image.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                      = local.app_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  service_plan_id           = azurerm_service_plan.this.id
  https_only                = true
  virtual_network_subnet_id = var.vnet_integration_subnet_id
  tags                      = local.tags

  # Containers deploy through the registry, never through FTP/WebDeploy.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    always_on                         = true
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    use_32_bit_worker                 = false
    load_balancing_mode               = "LeastRequests"
    vnet_route_all_enabled            = var.vnet_integration_subnet_id != null

    # Pull the image with the app's managed identity when an ACR is declared
    # (paired with the AcrPull role assignment below).
    container_registry_use_managed_identity = var.container_registry_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = local.container_registry_url
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.app_settings

  # Short-lived on-box log buffer for live log streaming; the durable store
  # is the Log Analytics workspace wired up in observability.tf.
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Rollouts: warm slots that mirror production.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "this" {
  for_each = toset(var.deployment_slots)

  name                      = each.key
  app_service_id            = azurerm_linux_web_app.this.id
  service_plan_id           = azurerm_service_plan.this.id
  https_only                = true
  virtual_network_subnet_id = var.vnet_integration_subnet_id
  tags                      = local.tags

  # Containers deploy through the registry, never through FTP/WebDeploy.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    always_on                         = true
    auto_swap_slot_name               = var.auto_swap_to_production ? azurerm_linux_web_app.this.name : null
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    use_32_bit_worker                 = false
    load_balancing_mode               = "LeastRequests"
    vnet_route_all_enabled            = var.vnet_integration_subnet_id != null

    # Pull the image with the slot's managed identity when an ACR is declared
    # (paired with the AcrPull role assignment below).
    container_registry_use_managed_identity = var.container_registry_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = local.container_registry_url
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.app_settings
}

# The app and every slot pull the image with their own managed identities
# (no registry credentials are configured on the apps). The web app is created
# first, so the very first container start can race the role assignment;
# App Service retries the pull until the grant propagates.
resource "azurerm_role_assignment" "acr_pull" {
  for_each = var.container_registry_id != null ? local.pull_principals : {}

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = each.value
}
