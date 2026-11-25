# ---------------------------------------------------------------------------
# Standard App Service module for containerized HTTP APIs.
#
# Opinions baked in (not configurable):
#   * Linux containers only, HTTPS-only, TLS >= 1.2, FTPS disabled, HTTP/2 on.
#   * System-assigned managed identity on the app and slot; private ACR pulls
#     use AcrPull - never registry passwords.
#   * Continuous-deployment webhook enabled; Terraform ignores drift on the
#     image tag so CD-driven rollouts are not reverted on the next apply.
#   * One resource group, plan, workspace and App Insights per service.
# ---------------------------------------------------------------------------

locals {
  tags = merge({ service = var.service_name }, var.tags)

  # --- Image reference parsing -------------------------------------------
  # A first path segment containing '.' or ':' is a registry host
  # (e.g. myacr.azurecr.io, localhost:5000); otherwise it is Docker Hub.
  image_segments       = split("/", var.container_image)
  explicit_registry    = can(regex("[.:]", local.image_segments[0]))
  docker_registry_url  = local.explicit_registry ? "https://${local.image_segments[0]}" : "https://index.docker.io"
  docker_image_name    = local.explicit_registry ? join("/", slice(local.image_segments, 1, length(local.image_segments))) : var.container_image
  registry_is_acr      = local.explicit_registry && endswith(local.image_segments[0], ".azurecr.io")
  use_managed_identity = local.registry_is_acr && var.acr_resource_id != null

  # --- Tier-dependent feature gates ---------------------------------------
  always_on      = contains(["F1", "D1"], var.sku_name) ? false : var.always_on
  slot_supported = can(regex("^[SPI][0-9]", var.sku_name))
  staging_active = var.staging_slot_enabled && local.slot_supported
  auto_swap      = local.staging_active && var.auto_swap_enabled
  zone_balancing = var.zone_redundant

  health_check_path = var.health_check_path != "" ? var.health_check_path : null
  health_eviction   = local.health_check_path != null ? 5 : null

  # --- Shared runtime configuration (app + staging slot) -------------------
  app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DOCKER_ENABLE_CI                    = "true"
    },
    var.enable_app_insights ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[0].connection_string
    } : {},
    var.extra_app_settings,
  )
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.service_name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                = "plan-${var.service_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = var.sku_name
  worker_count        = var.worker_count

  zone_balancing_enabled = local.zone_balancing

  tags = local.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || (can(regex("^P[0-9]+v[23]$", var.sku_name)) && var.worker_count >= 3)
      error_message = "zone_redundant requires a Premium v2/v3 SKU (e.g. P1v3) and worker_count >= 3."
    }
    precondition {
      condition     = !var.auto_swap_enabled || local.staging_active
      error_message = "auto_swap_enabled requires a staging slot; enable staging_slot_enabled and use an S*, P* or I* SKU."
    }
  }
}

# ---------------------------------------------------------------------------
# Production app
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.service_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only = true

  app_settings = local.app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = local.always_on
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = local.health_check_path
    health_check_eviction_time_in_min = local.health_eviction

    container_registry_use_managed_identity = local.use_managed_identity

    application_stack {
      docker_image_name   = local.docker_image_name
      docker_registry_url = local.docker_registry_url
    }
  }

  tags = local.tags

  lifecycle {
    # The CD webhook (DOCKER_ENABLE_CI) owns the running image tag after the
    # first deployment; do not fight it on subsequent applies.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

# ---------------------------------------------------------------------------
# Staging slot (rollouts): mirrors production configuration.
# Auto-swap, when enabled, is configured on the slot: it swaps itself into
# production once a deployment warms up successfully.
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = local.staging_active ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only = true

  app_settings = local.app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = local.always_on
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = local.health_check_path
    health_check_eviction_time_in_min = local.health_eviction
    auto_swap_slot_name               = local.auto_swap ? "production" : null

    container_registry_use_managed_identity = local.use_managed_identity

    application_stack {
      docker_image_name   = local.docker_image_name
      docker_registry_url = local.docker_registry_url
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

# ---------------------------------------------------------------------------
# Private registry access via managed identity (no stored credentials)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_acr_pull" {
  count = local.use_managed_identity ? 1 : 0

  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_acr_pull" {
  count = local.use_managed_identity && local.staging_active ? 1 : 0

  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
