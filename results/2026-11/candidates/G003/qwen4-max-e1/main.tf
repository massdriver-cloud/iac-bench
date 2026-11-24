locals {
  # Capacity: zone redundancy requires at least 3 workers; autoscale bounds
  # must always contain the default capacity.
  base_worker_count = var.zone_redundant ? max(var.instance_count, 3) : var.instance_count

  autoscale_minimum = var.zone_redundant ? max(var.autoscale_min, 3) : var.autoscale_min
  autoscale_maximum = max(var.autoscale_max, local.base_worker_count)
  autoscale_default = min(max(local.base_worker_count, local.autoscale_minimum), local.autoscale_maximum)

  use_acr_identity       = var.acr_id != null
  use_registry_basicauth = var.registry_username != null

  workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  # Settings the module owns so SREs never hand-tune App Service internals.
  managed_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    },
    var.enable_app_insights ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[0].connection_string
    } : {},
    local.use_registry_basicauth ? {
      DOCKER_REGISTRY_SERVER_URL      = var.container_registry_url
      DOCKER_REGISTRY_SERVER_USERNAME = var.registry_username
      DOCKER_REGISTRY_SERVER_PASSWORD = var.registry_password
    } : {}
  )

  app_settings      = merge(local.managed_app_settings, var.app_settings)
  slot_app_settings = merge(local.managed_app_settings, var.slot_app_settings)
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Capacity: one plan per service, CPU-autoscaled (see monitoring.tf)
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = local.base_worker_count
  zone_balancing_enabled = var.zone_redundant

  tags = var.tags

  lifecycle {
    # After creation the live worker count is owned by Azure autoscale;
    # ignore drift so applies don't fight the scale engine.
    ignore_changes = [worker_count]
  }
}

# ---------------------------------------------------------------------------
# Production app: Linux container, hardened defaults
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  public_network_access_enabled = true
  virtual_network_subnet_id     = var.subnet_id
  app_settings                  = local.app_settings

  # The container image is the deployment unit: no FTP/zip-deploy with
  # publishing-profile basic auth.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    use_32_bit_worker                       = false
    vnet_route_all_enabled                  = var.subnet_id != null
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = local.use_acr_identity

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Rollouts: staging slot on the same plan (no extra compute cost)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true
  app_settings   = local.slot_app_settings

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    use_32_bit_worker                       = false
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = local.use_acr_identity
    auto_swap_slot_name                     = var.auto_swap_enabled ? "production" : null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Registry access via managed identity (preferred over stored credentials)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_acr_pull" {
  count = local.use_acr_identity ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "slot_acr_pull" {
  count = local.use_acr_identity && var.enable_staging_slot ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
