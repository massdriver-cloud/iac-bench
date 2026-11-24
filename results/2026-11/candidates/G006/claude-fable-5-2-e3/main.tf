data "azurerm_client_config" "current" {}

locals {
  is_prod = var.environment == "prod"

  resource_group_name = coalesce(var.resource_group_name, "${var.application}-${var.environment}")

  # Storage account names are global across Azure, 3-24 chars, lowercase
  # alphanumeric only: "st" + app (<=12) + env (<=4) + 6-char hash = <=24.
  # The hash is stable for a given subscription / resource group / app / env,
  # so the name never changes between runs but does not collide with other
  # tenants that happen to have an "orders" application too.
  env_short   = { dev = "dev", test = "test", staging = "stg", prod = "prod" }[var.environment]
  app_compact = substr(replace(var.application, "-", ""), 0, 12)
  name_hash = substr(sha256(join("/", [
    data.azurerm_client_config.current.subscription_id,
    lower(local.resource_group_name),
    var.application,
    var.environment,
  ])), 0, 6)
  storage_account_name = coalesce(var.storage_account_name, "st${local.app_compact}${local.env_short}${local.name_hash}")

  replication_type = coalesce(var.replication_type, local.is_prod ? "GZRS" : "LRS")

  # Recovery windows.
  #   soft delete : deleted blobs / containers can be undeleted for this long
  #   restore     : containers can be rolled back to any point in this window
  #                 (must be shorter than soft delete)
  #   versions    : overwritten or deleted versions are kept this long, then
  #                 cleaned up so they do not accumulate cost forever
  soft_delete_days       = local.is_prod ? 30 : 7
  point_in_time_days     = local.soft_delete_days - 1
  version_retention_days = local.is_prod ? 90 : 14

  delete_lock_enabled = coalesce(var.delete_lock_enabled, local.is_prod)

  expiring_containers = {
    for name, c in var.containers : name => c.delete_after_days if c.delete_after_days != null
  }

  tags = merge(var.tags, {
    application = var.application
    environment = var.environment
    managed-by  = "opentofu"
  })
}

# ---------------------------------------------------------------------------
# Storage account
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Encryption in transit.
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Encryption at rest is always on (platform-managed keys); add the second,
  # infrastructure-level layer because it can only be chosen at creation.
  infrastructure_encryption_enabled = true

  # Identity-only access: no account keys, no key-based SAS, no anonymous
  # access, no local (SFTP) users. Applications authenticate with their own
  # Entra ID identity.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  local_user_enabled              = false
  sftp_enabled                    = false

  # Keep data inside the tenant.
  cross_tenant_replication_enabled = false
  allowed_copy_scope               = "AAD"

  # Private-only: reachable solely through the private endpoint below.
  public_network_access_enabled = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    change_feed_retention_in_days = local.soft_delete_days

    delete_retention_policy {
      days = local.soft_delete_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }

    restore_policy {
      days = local.point_in_time_days
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Containers (managed through ARM, so no data-plane access is needed to deploy)
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Housekeeping: keep old versions for a while, then remove them; expire files
# in containers that asked for it.
# ---------------------------------------------------------------------------

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-previous-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.version_retention_days
      }
      snapshot {
        delete_after_days_since_creation_greater_than = local.version_retention_days
      }
    }
  }

  dynamic "rule" {
    for_each = local.expiring_containers

    content {
      name    = "expire-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          delete_after_days_since_creation_greater_than = rule.value
        }
      }
    }
  }

  depends_on = [azurerm_storage_container.this]
}

# ---------------------------------------------------------------------------
# Access: the application's identity may read, write and delete blobs in the
# containers this module created - and nothing broader than that.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "application" {
  for_each = azurerm_storage_container.this

  scope                = each.value.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Read/write access for the ${var.application} application (${var.environment})."
}

# ---------------------------------------------------------------------------
# Network path: private endpoint for the blob service
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${local.storage_account_name}-blob"
  resource_group_name = local.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id == null ? [] : [var.private_dns_zone_id]

    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Audit logging (when a workspace is supplied)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "audit-to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

# ---------------------------------------------------------------------------
# Delete protection
# ---------------------------------------------------------------------------

resource "azurerm_management_lock" "this" {
  count = local.delete_lock_enabled ? 1 : 0

  name       = "do-not-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Holds ${var.application} application data (${var.environment}). Managed by the standard storage module; set delete_lock_enabled = false there to remove."

  # Created last and removed first, so a deliberate teardown is not blocked by
  # the lock while everything underneath it is being deleted.
  depends_on = [
    azurerm_storage_container.this,
    azurerm_storage_management_policy.this,
    azurerm_role_assignment.application,
    azurerm_private_endpoint.blob,
    azurerm_monitor_diagnostic_setting.blob,
  ]
}
