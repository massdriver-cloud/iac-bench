locals {
  name_suffix = "${var.service_name}-${var.environment}"

  names = {
    resource_group = "rg-${local.name_suffix}"
    service_plan   = "plan-${local.name_suffix}"
    app            = "app-${local.name_suffix}"
    log_analytics  = "log-${local.name_suffix}"
    app_insights   = "ai-${local.name_suffix}"
    autoscale      = "autoscale-${local.name_suffix}"
    diag_app       = "diag-app-${local.name_suffix}"
    diag_plan      = "diag-plan-${local.name_suffix}"
    lock_app       = "lock-app-${local.name_suffix}"
  }

  default_tags = {
    service     = var.service_name
    environment = var.environment
    module      = "app-service-standard"
    managed_by  = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)

  # Zone-redundant plans must run at least 3 instances (one per zone), so we
  # enforce that floor regardless of what minimum_instance_count asks for.
  minimum_instances = max(var.minimum_instance_count, var.zone_redundant ? 3 : 1)

  # Bring-your-own Log Analytics workspace support: fall back to the workspace
  # this module creates.
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  # Standard runtime settings applied to both the production app and the
  # staging slot.
  app_settings = merge(
    {
      # The container image carries its own binaries; do not mount the App
      # Service content share into the runtime.
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      # Port the container listens on. App Service assumes 80 unless told.
      WEBSITES_PORT = tostring(var.container_port)
      # Wire the platform and SDK-level telemetry to Application Insights.
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    },
    var.health_check_enabled ? {
      # After this many consecutive failed probes an instance is marked
      # unhealthy, taken out of rotation and replaced.
      WEBSITE_HEALTHCHECK_MAXPINGFAILURES        = "2"
      WEBSITE_HEALTHCHECK_MAXCONSECUTIVEFAILURES = "2"
    } : {},
    var.extra_app_settings,
  )
}
