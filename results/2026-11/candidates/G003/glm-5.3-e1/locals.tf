locals {
  # Resource group: either the dedicated one created by this module or an
  # existing group supplied by the caller.
  created_resource_group_name = one(azurerm_resource_group.this[*].name)
  resource_group_name         = var.create_resource_group ? local.created_resource_group_name : var.resource_group_name

  tags = merge(
    var.tags,
    {
      managed_by = "opentofu"
      module     = "sre-app-service"
      app        = var.name
    },
  )

  # Container registry wiring. An ACR resource ID switches the app to managed
  # identity pulls; its login server is derived from the registry name unless
  # an explicit URL is given. Without either, public Docker Hub is assumed.
  registry_use_managed_identity = var.acr_resource_id != null

  registry_url = var.container_registry_url != null ? var.container_registry_url : (
    var.acr_resource_id != null ? "https://${basename(var.acr_resource_id)}.azurecr.io" : "https://index.docker.io"
  )

  # The staging slot runs a candidate build when one is pinned, otherwise it
  # mirrors production.
  staging_image = var.staging_container_image != null ? var.staging_container_image : var.container_image

  # App settings: the module owns observability/storage switches on top of the
  # caller-provided environment.
  app_settings = merge(
    var.app_settings,
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE   = tostring(var.enable_app_service_storage)
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    },
  )

  # Alert delivery. Deliberately computed from variables only (never from
  # resource attributes), so the alert resources' count is known at plan time.
  # Existing action groups come from `action_group_ids`; the module's own
  # action group exists exactly when `alert_emails` is non-empty.
  alerts_enabled = length(var.alert_emails) > 0 || length(var.action_group_ids) > 0

  # Auto-heal policy passed to the site_config dynamic block (empty = off).
  auto_heal_policy = var.auto_heal != null ? { enabled = var.auto_heal } : {}

  # Slot endpoints (null when the staging slot is disabled).
  staging_hostname = one(azurerm_linux_web_app_slot.staging[*].default_hostname)
  staging_url      = local.staging_hostname != null ? "https://${local.staging_hostname}" : null
}
