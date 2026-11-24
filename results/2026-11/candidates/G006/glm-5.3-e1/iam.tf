# =============================================================================
# Access for the application's Entra ID identities
# =============================================================================

# The application identity is the front door: each object ID passed in
# identity_object_ids gets "Storage Blob Data Contributor" (read, write and
# delete blobs and containers) at the storage account scope. Data-plane
# access then flows through Entra ID exactly as AKS workload identity and
# App Service managed identity expect, and - because account keys are
# disabled - there is no second, unattributable front door.

locals {
  # Deterministic, GUID-shaped assignment names derived from
  # (scope, role, principal). Re-running or re-creating a stack reuses the
  # same assignment instead of piling up new random GUIDs.
  role_assignment_digests = {
    for principal_id in var.identity_object_ids :
    principal_id => md5("${azurerm_storage_account.this.id}/storage-blob-data-contributor/${principal_id}")
  }

  role_assignment_names = {
    for principal_id, digest in local.role_assignment_digests :
    principal_id => format(
      "%s-%s-%s-%s-%s",
      substr(digest, 0, 8),
      substr(digest, 8, 4),
      substr(digest, 12, 4),
      substr(digest, 16, 4),
      substr(digest, 20, 12)
    )
  }
}

resource "azurerm_role_assignment" "app_identity" {
  for_each = toset(var.identity_object_ids)

  name                 = local.role_assignment_names[each.value]
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
