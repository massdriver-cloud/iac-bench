locals {
  # Settings every service gets. var.app_settings is merged last so SREs can
  # override deliberately, but the defaults are correct for a containerized
  # HTTP API out of the box.
  default_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false" # containers are stateless; no home mount
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }

  app_settings = merge(local.default_app_settings, var.app_settings)

  common_tags = merge(
    {
      managed_by = "opentofu"
      service    = var.name
    },
    var.tags,
  )
}

# ---------------------------------------------------------------------------
# Capacity: one plan per service. Instance count is a floor; the autoscale
# setting owns it from there (worker_count drift is ignored on purpose).
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-asp"
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_capacity
  zone_balancing_enabled = var.zone_redundant

  tags = local.common_tags

  lifecycle {
    # Autoscale adjusts the live instance count; don't fight it.
    ignore_changes = [worker_count]

    precondition {
      condition     = var.max_capacity >= var.min_capacity
      error_message = "max_capacity must be greater than or equal to min_capacity."
    }

    precondition {
      condition     = var.zone_redundant ? var.min_capacity >= 2 : true
      error_message = "Zone redundancy requires min_capacity >= 2."
    }

    precondition {
      condition     = var.zone_redundant ? can(regex("^(?i)(p|i)", var.sku_name)) : true
      error_message = "Zone redundancy requires a Premium (P*) or Isolated (I*) SKU."
    }
  }
}

# ---------------------------------------------------------------------------
# The service itself: containerized HTTP API, hardened defaults.
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                      = var.name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.this.id
  https_only                = true
  client_affinity_enabled   = false # stateless APIs don't need sticky sessions
  virtual_network_subnet_id = var.vnet_integration_subnet_id

  # Publish with RBAC (CI service principal / OIDC), not basic-auth profiles.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 5

    container_registry_use_managed_identity = var.container_registry_id != null

    application_stack {
      docker_image_name   = var.image
      docker_registry_url = var.registry_url
    }

    dynamic "auto_heal_setting" {
      for_each = var.auto_heal_enabled ? [true] : []

      content {
        trigger {
          status_code {
            count             = 25
            interval          = "00:05:00"
            status_code_range = "500-599"
          }
        }
        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = "00:01:00"
        }
      }
    }
  }

  app_settings = local.app_settings

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Rollouts: a staging slot that mirrors production. Deploy the new image to
# the slot, warm it, then swap. Swap is an operational action, not something
# the module performs.
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name                      = "staging"
  app_service_id            = azurerm_linux_web_app.this.id
  https_only                = true
  client_affinity_enabled   = false
  virtual_network_subnet_id = var.vnet_integration_subnet_id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 5

    container_registry_use_managed_identity = var.container_registry_id != null

    application_stack {
      docker_image_name   = var.image
      docker_registry_url = var.registry_url
    }
  }

  app_settings = local.app_settings

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Container pulls: no admin credentials, the managed identity gets AcrPull.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = var.container_registry_id != null && var.staging_slot_enabled ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
