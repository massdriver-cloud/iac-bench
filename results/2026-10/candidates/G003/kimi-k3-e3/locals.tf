locals {
  # Use the caller's workspace when given, otherwise the one we create.
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  # App settings the module owns: container port, no persistent storage for
  # stateless containers, and Application Insights wiring. var.app_settings
  # is merged last so callers can override deliberately.
  app_settings = merge(
    {
      "WEBSITES_PORT"                              = tostring(var.container_port)
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"        = "false"
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this.connection_string
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    },
    var.app_settings,
  )
}
