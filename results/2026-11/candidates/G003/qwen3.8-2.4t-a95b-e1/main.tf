# -----------------------------------------------------------------------------
# Locals: naming, tags and the shared app-settings baseline.
# -----------------------------------------------------------------------------

locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name}-rg")

  # azurerm 4.x takes the container reference as a single 'name:tag' string.
  container_image = "${var.image_name}:${var.image_tag}"

  tags = merge(
    {
      service    = var.name
      managed-by = "opentofu"
    },
    var.tags,
  )

  # Standard settings every service gets. Application Insights wiring makes
  # instrumentation a zero-code-change default for containerized apps.
  default_app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key
    WEBSITES_PORT                         = tostring(var.container_port)
    # Custom containers don't need the shared storage mount; disabling it
    # avoids a common class of container startup failures.
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
  }

  app_settings = merge(local.default_app_settings, var.additional_app_settings)

  law_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  # Capacity bookkeeping for the autoscale profile.
  autoscale_min = coalesce(var.autoscale_min_instances, var.instance_count)
  autoscale_max = max(var.autoscale_max_instances, local.autoscale_min)
}

# -----------------------------------------------------------------------------
# Placement & capacity.
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # Linux plans are 'reserved'; required for Linux containers.
  os_type  = "Linux"
  sku_name = var.sku_name

  worker_count           = var.instance_count
  zone_balancing_enabled = var.zone_balancing_enabled

  tags = local.tags
}

# CPU-based scale-out/scale-in so capacity follows load without hand-tuning.
resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "default"

    capacity {
      default = local.autoscale_min
      minimum = local.autoscale_min
      maximum = local.autoscale_max
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        operator           = "GreaterThan"
        threshold          = var.scale_out_cpu_threshold
        statistic          = "Average"
        time_aggregation   = "Average"
        time_grain         = "PT1M"
        time_window        = "PT5M"
      }

      scale_action {
        type      = "ChangeCount"
        direction = "Increase"
        value     = 1
        cooldown  = "PT10M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        operator           = "LessThan"
        threshold          = var.scale_in_cpu_threshold
        statistic          = "Average"
        time_aggregation   = "Average"
        time_grain         = "PT1M"
        time_window        = "PT5M"
      }

      scale_action {
        type      = "ChangeCount"
        direction = "Decrease"
        value     = 1
        cooldown  = "PT5M"
      }
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# The service: a Linux web app running a container.
# Standard posture: HTTPS-only, TLS 1.2+, no FTP(S), always-on, health
# probing with eviction of failing instances, system-assigned identity.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                = true
  virtual_network_subnet_id = var.virtual_network_subnet_id

  tags = local.tags

  # Identity lets the service use managed auth for Azure resources and, with
  # container_registry_id, pull images without secrets.
  identity {
    type = "SystemAssigned"
  }

  app_settings = local.app_settings

  site_config {
    always_on           = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"

    # Health: probe the service; evict instances that keep failing so the
    # platform replaces them (self-healing).
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    vnet_route_all_enabled = var.virtual_network_subnet_id != null

    container_registry_use_managed_identity = var.container_registry_id != null && var.container_registry_username == null

    application_stack {
      docker_registry_url      = var.image_registry_url
      docker_image_name        = local.container_image
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }
}

# -----------------------------------------------------------------------------
# Rollouts: staging slot mirroring the production configuration.
# Deploy a new tag to staging, verify, then swap (manually, or automatically
# with auto_swap_enabled).
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only                = true
  virtual_network_subnet_id = var.virtual_network_subnet_id

  tags = local.tags

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.app_settings

  site_config {
    always_on           = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"

    auto_swap_slot_name = var.auto_swap_enabled ? "production" : null

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    vnet_route_all_enabled = var.virtual_network_subnet_id != null

    container_registry_use_managed_identity = var.container_registry_id != null && var.container_registry_username == null

    application_stack {
      docker_registry_url      = var.image_registry_url
      docker_image_name        = local.container_image
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }
}

# -----------------------------------------------------------------------------
# Secret-free pulls: grant the app identity AcrPull on a private ACR.
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}
