# ---------------------------------------------------------------------------
# Data access for the application's identities.
#
# Judgment: RBAC via Entra ID is the only standard access path, so the module
# grants each identity the least set of built-in data roles that covers what
# the account actually contains: blob always (every account has blob
# containers conceptually), queue/file only when in use.
# ---------------------------------------------------------------------------

locals {
  app_data_roles = concat(
    ["Storage Blob Data Contributor"],
    length(var.queues) > 0 ? ["Storage Queue Data Contributor"] : [],
    length(var.file_shares) > 0 ? ["Storage File Data SMB Share Contributor"] : [],
  )

  app_role_assignments = {
    for pair in setproduct(var.app_identity_object_ids, local.app_data_roles) :
    "${pair[0]}:${pair[1]}" => {
      principal_id         = pair[0]
      role_definition_name = pair[1]
    }
  }
}

resource "azurerm_role_assignment" "app_data_access" {
  for_each = local.app_role_assignments

  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}
