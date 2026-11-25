locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  location            = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location
  workspace_id        = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  use_acr_managed_identity = var.container_registry_id != null

  # Settings every service gets: observability wiring plus swap warmup, so a
  # slot must pass the health check before it takes production traffic.
  default_app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200-299"
  }
  app_settings = merge(local.default_app_settings, var.app_settings)
}

# -----------------------------------------------------------------------------
# Placement
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Capacity: Linux Premium plan, zone-balanced, CPU-autoscaled
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                = "asp-${var.service_name}"
  resource_group_name = local.resource_group_name
  location            = local.location

  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_redundant

  tags = var.tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscaling.enabled ? 1 : 0

  name                = "as-${var.service_name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true

  profile {
    name = "cpu"

    capacity {
      minimum = tostring(var.autoscaling.min_instances)
      maximum = tostring(var.autoscaling.max_instances)
      default = tostring(var.worker_count)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscaling.scale_out_cpu_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscaling.scale_in_cpu_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Observability: Log Analytics + workspace-based Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "log-${var.service_name}"
  resource_group_name = local.resource_group_name
  location            = local.location

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.service_name}"
  resource_group_name = local.resource_group_name
  location            = local.location

  application_type     = "web"
  workspace_id         = local.workspace_id
  sampling_percentage  = var.sampling_percentage
  daily_data_cap_in_gb = var.daily_data_cap_gb

  tags = var.tags
}

# -----------------------------------------------------------------------------
# The app itself
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.service_name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only              = true
  client_affinity_enabled = false # stateless HTTP APIs: no ARR affinity cookie

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
    health_check_path   = var.health_check_path

    # Replace an instance that keeps failing its health check.
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    # Pull from ACR with the managed identity instead of stored credentials.
    container_registry_use_managed_identity = local.use_acr_managed_identity

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = local.app_settings

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Warning"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Rollouts: staging slot for blue-green deployments
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "this" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"

    # The provider requires both health check arguments together on slots.
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    container_registry_use_managed_identity = local.use_acr_managed_identity
  }

  app_settings = local.app_settings

  tags = var.tags
}

# Image pull permissions. Only created when an ACR resource ID is supplied;
# each identity (app and slot) needs its own grant.
resource "azurerm_role_assignment" "app_acr_pull" {
  count = local.use_acr_managed_identity ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "slot_acr_pull" {
  count = local.use_acr_managed_identity && var.staging_slot_enabled ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.this[0].identity[0].principal_id
}

# -----------------------------------------------------------------------------
# Observability: stream platform + app logs and metrics to Log Analytics
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${var.service_name}-app"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "slot" {
  count = var.staging_slot_enabled ? 1 : 0

  name                       = "diag-${var.service_name}-slot"
  target_resource_id         = azurerm_linux_web_app_slot.this[0].id
  log_analytics_workspace_id = local.workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
