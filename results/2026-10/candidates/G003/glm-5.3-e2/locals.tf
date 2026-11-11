locals {
  create_resource_group = var.resource_group_name == null
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  # Environment settings applied to production and every slot. The module's own
  # keys are merged last so the standard wiring (no SMB-backed /home, container
  # port, telemetry) always holds.
  base_app_settings = merge(
    var.app_settings,
    { WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false" },
    var.image.port == null ? {} : { WEBSITES_PORT = tostring(var.image.port) },
  )

  # App settings pinned to slots so telemetry never swaps with deployments.
  telemetry_app_setting_names = [
    "APPLICATIONINSIGHTS_CONNECTION_STRING",
    "APPINSIGHTS_INSTRUMENTATIONKEY",
  ]

  # Managed identity principals (app + slots) that may need AcrPull on the
  # container registry.
  acr_pull_principals = merge(
    { app = azurerm_linux_web_app.this.identity[0].principal_id },
    { for name, slot in azurerm_linux_web_app_slot.this : name => slot.identity[0].principal_id },
  )

  # `image` is a sensitive variable (it can carry a registry password); the
  # managed-identity flag and the registry resource id are not secrets, so it is
  # safe to branch on them through nonsensitive().
  grant_acr_pull = nonsensitive(var.image.use_managed_identity) && nonsensitive(var.image.registry_id) != null

  workspace_id = var.observability.workspace_id != null ? var.observability.workspace_id : azurerm_log_analytics_workspace.this[0].id

  autoscale_enabled = var.capacity.max_instances != null && var.capacity.max_instances > var.capacity.min_instances

  diagnostic_targets = merge(
    { app = azurerm_linux_web_app.this.id },
    { for name, slot in azurerm_linux_web_app_slot.this : name => slot.id },
  )
}
