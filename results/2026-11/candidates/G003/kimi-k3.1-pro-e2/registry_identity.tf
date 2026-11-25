variable "container_registry_managed_identity_principal_id" {
  description = "Principal ID corresponding to container_registry_managed_identity_client_id. Required for the module-managed AcrPull grant when a user-assigned registry identity is selected."
  type        = string
  default     = null
}

resource "azurerm_role_assignment" "production_acr_pull" {
  count = var.container_registry_use_managed_identity && var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = var.container_registry_managed_identity_client_id != null ? var.container_registry_managed_identity_principal_id : azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_acr_pull" {
  # A user-assigned registry identity is shared by both slots and only needs
  # the production_acr_pull grant above. System identities are slot-specific.
  count = var.deployment_slot_enabled && var.container_registry_use_managed_identity && var.container_registry_id != null && var.container_registry_managed_identity_client_id == null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
