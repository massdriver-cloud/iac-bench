###############################################################################
# Who can use the data
###############################################################################

# The application itself: read, write and delete blobs in this account. The
# role also lets the app mint short-lived, identity-signed ("user delegation")
# download/upload links, so account keys are never needed.
resource "azurerm_role_assignment" "application" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal" # managed identities and app registrations alike
  description          = "${var.application} (${var.environment}) application identity - managed by the app-storage module."
}

# Optional people / jobs that only need to look.
resource "azurerm_role_assignment" "read_only" {
  for_each = var.read_only_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
  description          = "Read-only access for '${each.key}' - managed by the app-storage module."
}

###############################################################################
# Private endpoint (optional)
###############################################################################

locals {
  private_endpoint_name = "pe-${local.storage_account_name}-blob"

  # Two ways the private endpoint's DNS record gets created:
  #  - this module registers it in the zone(s) given in private_dns_zone_ids, or
  #  - nothing is given and the platform does it centrally (Azure Policy), in
  #    which case the module must not undo what the policy attached.
  # "ignore that attribute" cannot be switched on and off per input, hence the
  # two variants of the same resource below. Exactly one of them is created.
  private_endpoint_module_dns   = local.private_endpoint && length(var.private_dns_zone_ids) > 0
  private_endpoint_platform_dns = local.private_endpoint && length(var.private_dns_zone_ids) == 0

  private_endpoints = concat(
    azurerm_private_endpoint.blob[*],
    azurerm_private_endpoint.blob_platform_dns[*],
  )
}

resource "azurerm_private_endpoint" "blob" {
  count = local.private_endpoint_module_dns ? 1 : 0

  name                          = local.private_endpoint_name
  resource_group_name           = local.resource_group_name
  location                      = local.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-${local.private_endpoint_name}"

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = var.private_dns_zone_ids
  }

  tags = local.tags
}

resource "azurerm_private_endpoint" "blob_platform_dns" {
  count = local.private_endpoint_platform_dns ? 1 : 0

  name                          = local.private_endpoint_name
  resource_group_name           = local.resource_group_name
  location                      = local.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-${local.private_endpoint_name}"

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  tags = local.tags

  lifecycle {
    # The DNS zone group is attached by the platform; leave it alone.
    ignore_changes = [private_dns_zone_group]
  }
}

# A locked-down account nobody can reach is a confusing thing to debug, so say
# so at plan time instead of letting the app find out with a 403.
check "application_can_reach_storage" {
  assert {
    condition     = local.has_network_path
    error_message = "The storage firewall blocks all traffic and no way in has been configured, so the application will not be able to reach its storage yet. Set allowed_subnet_ids to the subnet(s) the app runs in (AKS node subnet, App Service VNet-integration subnet) and/or private_endpoint_subnet_id."
  }
}

###############################################################################
# Audit trail (optional)
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "audit-to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Who changed or deleted what. Reads are left out on purpose: for media-heavy
  # applications they dwarf everything else in volume and cost.
  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

###############################################################################
# Delete lock (prod by default)
###############################################################################

resource "azurerm_management_lock" "delete" {
  count = local.delete_lock_enabled ? 1 : 0

  name       = "do-not-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Holds ${var.application} ${var.environment} application data. Managed by the app-storage module (delete_lock_enabled)."

  # Create the lock last and remove it first, so that it never blocks this
  # module's own create / destroy of the things underneath the account.
  depends_on = [
    azurerm_storage_container.this,
    azurerm_storage_management_policy.this,
    azurerm_role_assignment.application,
    azurerm_role_assignment.read_only,
    azurerm_private_endpoint.blob,
    azurerm_private_endpoint.blob_platform_dns,
    azurerm_monitor_diagnostic_setting.blob,
  ]
}
