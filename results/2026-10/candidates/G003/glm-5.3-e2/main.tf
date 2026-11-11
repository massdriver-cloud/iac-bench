# -----------------------------------------------------------------------------
# Resource group: one service, one resource group (created unless supplied).
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Capacity: a dedicated Linux plan per service, so services never share a
# capacity or availability domain. Sized from `capacity`; autoscaling is
# layered on top in autoscale.tf.
#
# Availability note: this provider generation (azurerm 4.81) exposes no
# zone-redundancy switch on `azurerm_service_plan` (it was removed along with
# the `capacity` -> `worker_count` rename; only the deprecated
# `azurerm_app_service_plan`, scheduled for removal in v5.0, still accepts
# one). The module therefore encodes its availability posture as an instance
# floor: Premium plans with >= 3 instances are what App Service spreads across
# availability zones, so `capacity.min_instances` defaults to 3.
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = local.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.capacity.instance_size
  worker_count        = var.capacity.min_instances
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# The service: a Linux web app running the container image.
#
# Internals decided here, once, for every service: always on, HTTPS only,
# TLS 1.2, FTPS off, HTTP/2, no session affinity, system-assigned identity,
# health-check eviction, diagnostics on.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  client_affinity_enabled       = false
  public_network_access_enabled = var.network.public_network_access_enabled
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    min_tls_version                   = "1.2"
    health_check_path                 = var.health.enabled ? var.health.path : null
    health_check_eviction_time_in_min = var.health.enabled ? var.health.eviction_minutes : null
    virtual_network_subnet_id         = var.network.subnet_id
    app_command_line                  = var.image.startup_command

    application_stack {
      docker_image                            = var.image.name
      docker_image_tag                        = var.image.tag
      docker_registry_url                     = var.image.registry_url
      docker_registry_username                = var.image.registry_username
      docker_registry_password                = var.image.registry_password
      container_registry_use_managed_identity = var.image.use_managed_identity
    }
  }

  app_settings = merge(
    local.base_app_settings,
    {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
      APPINSIGHTS_INSTRUMENTATIONKEY       = azurerm_application_insights.this.instrumentation_key
    },
  )

  dynamic "connection_strings" {
    for_each = var.connection_strings
    content {
      name  = connection_strings.value.name
      type  = connection_strings.value.type
      value = connection_strings.value.value
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      filesystem {
        retention_in_days = 1
        retention_in_mb   = 35
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Rollout: deployment slots that mirror production. Each slot can pin a
# candidate `image_tag`, carries its own App Insights component (pinned via
# sticky settings), its own identity and its own diagnostic settings, so it is
# a fully warm pre-production environment and swaps are boring.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "this" {
  for_each = { for slot in var.rollout.slots : slot.name => slot }

  name                = each.key
  app_service_name    = azurerm_linux_web_app.this.name
  resource_group_name = local.resource_group_name

  https_only                    = true
  client_affinity_enabled       = false
  public_network_access_enabled = var.network.public_network_access_enabled
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    min_tls_version                   = "1.2"
    health_check_path                 = var.health.enabled ? var.health.path : null
    health_check_eviction_time_in_min = var.health.enabled ? var.health.eviction_minutes : null
    virtual_network_subnet_id         = var.network.subnet_id
    app_command_line                  = var.image.startup_command

    application_stack {
      docker_image                            = var.image.name
      docker_image_tag                        = each.value.image_tag != null ? each.value.image_tag : var.image.tag
      docker_registry_url                     = var.image.registry_url
      docker_registry_username                = var.image.registry_username
      docker_registry_password                = var.image.registry_password
      container_registry_use_managed_identity = var.image.use_managed_identity
    }
  }

  app_settings = merge(
    local.base_app_settings,
    {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.slots[each.key].connection_string
      APPINSIGHTS_INSTRUMENTATIONKEY       = azurerm_application_insights.slots[each.key].instrumentation_key
    },
  )

  dynamic "connection_strings" {
    for_each = var.connection_strings
    content {
      name  = connection_strings.value.name
      type  = connection_strings.value.type
      value = connection_strings.value.value
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      filesystem {
        retention_in_days = 1
        retention_in_mb   = 35
      }
    }
  }

  sticky_settings {
    app_setting_names       = concat(local.telemetry_app_setting_names, var.rollout.sticky_app_setting_names)
    connection_string_names = var.rollout.sticky_connection_string_names
  }
}
