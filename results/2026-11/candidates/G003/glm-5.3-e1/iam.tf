# -----------------------------------------------------------------------------
# Identity: the app (and its staging slot) each get a system-assigned managed
# identity. When acr_resource_id is set, both are granted AcrPull so image
# pulls need no stored credentials.
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  count = var.acr_resource_id != null ? 1 : 0

  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging_slot" {
  count = var.acr_resource_id != null && var.enable_staging_slot ? 1 : 0

  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
