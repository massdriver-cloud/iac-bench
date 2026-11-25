# =============================================================================
# Entra ID RBAC — Primary Application Identity
# =============================================================================

resource "azurerm_role_assignment" "application" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = var.application_role
  principal_id                     = var.application_principal_id
  skip_service_principal_aad_check = true
  description                      = "Managed by OpenTofu: ${var.application_name} (${var.environment}) application identity access."
}

# =============================================================================
# Entra ID RBAC — Optional User Delegation SAS (Direct Browser Uploads/Media)
# =============================================================================

resource "azurerm_role_assignment" "user_delegation_sas" {
  count = var.enable_user_delegation_sas ? 1 : 0

  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Delegator"
  principal_id                     = var.application_principal_id
  skip_service_principal_aad_check = true
  description                      = "Managed by OpenTofu: allows ${var.application_name} (${var.environment}) to issue short-lived User Delegation SAS tokens without shared account keys."
}

# =============================================================================
# Entra ID RBAC — Optional Additional Principals (Account or Container Scoped)
# =============================================================================

resource "azurerm_role_assignment" "additional" {
  for_each = var.additional_role_assignments

  scope = (
    each.value.container_name != null
    ? "${azurerm_storage_account.this.id}/blobServices/default/containers/${azurerm_storage_container.this[each.value.container_name].name}"
    : azurerm_storage_account.this.id
  )
  role_definition_name = each.value.role_name
  principal_id         = each.value.principal_id
  description          = coalesce(each.value.description, "Managed by OpenTofu: additional access (${each.key}) for ${var.application_name} (${var.environment}).")

  lifecycle {
    precondition {
      condition     = each.value.container_name == null || contains(keys(var.containers), each.value.container_name)
      error_message = "additional_role_assignments[\"${each.key}\"].container_name must match a container defined in var.containers."
    }
  }
}
