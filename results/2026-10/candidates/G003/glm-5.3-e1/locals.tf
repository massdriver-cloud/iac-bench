locals {
  # Resource group: module-owned by default, or supplied by the caller.
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : azurerm_resource_group.this[0].name

  tags = merge(
    var.tags,
    {
      service    = var.name
      managed_by = "terraform"
    },
  )

  # Registry access: Azure Container Registry via managed identity (preferred),
  # basic-auth credentials for other registries, or anonymous (public) pull.
  use_acr_managed_identity = var.container_registry_id != null

  # Full image reference: registry host (for anything but Docker Hub) + tag.
  docker_image_name = "${var.container_image}:${var.container_tag}"

  # Health: App Service built-in health check; "" disables it entirely.
  health_check_path = var.health_check_path == "" ? null : var.health_check_path

  # The synthetic availability test probes the same path (fall back to /).
  availability_probe_path = coalesce(local.health_check_path, "/")

  # The synthetic test can only see the app when it is publicly reachable.
  enable_availability_test = var.enable_availability_test && var.public_network_access_enabled && length(var.allowed_ip_address_ranges) == 0

  builtin_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key
  }

  # Module-managed settings always win so observability stays wired no
  # matter what the caller passes in app_settings.
  app_settings = merge(var.app_settings, local.builtin_app_settings)

  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  diagnostic_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs",
  ]

  # Principals that need AcrPull when pulling from a private ACR.
  acr_pull_principals = merge(
    { production = azurerm_linux_web_app.this.identity[0].principal_id },
    var.enable_staging_slot ? { staging = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id } : {},
  )
}
