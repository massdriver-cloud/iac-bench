###############################################################################
# Context: the application's existing resource group
###############################################################################

data "azurerm_client_config" "current" {}

# Looked up, never created: every application already owns one resource group
# per environment. A typo in the name fails here, at plan time.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.this.location)

  # Storage account names are global across all of Azure, 3-24 characters,
  # lowercase letters and digits only. Derive one that is readable
  # ("orders-prod" -> "stordersprod<hash>"), valid, and stable: the hash only
  # depends on the subscription and resource group, so it never changes.
  name_stem            = substr(lower(replace(var.resource_group_name, "/[^0-9A-Za-z]/", "")), 0, 16)
  name_hash            = substr(sha256("${data.azurerm_client_config.current.subscription_id}/${lower(var.resource_group_name)}"), 0, 6)
  storage_account_name = coalesce(var.storage_account_name, "st${local.name_stem}${local.name_hash}")

  tags = merge(
    data.azurerm_resource_group.this.tags,
    var.tags,
    {
      "managed-by" = "opentofu"
      "module"     = "app-storage"
    },
  )

  # Service endpoints and IP rules are served by the public endpoint (behind
  # the firewall). If neither is used, the public endpoint is switched off
  # completely and only a private endpoint can reach the account.
  public_endpoint_needed = (
    var.allow_public_network_access ||
    length(var.allowed_subnet_ids) > 0 ||
    length(var.allowed_ip_ranges) > 0
  )

  network_path_configured = local.public_endpoint_needed || var.private_endpoint_subnet_id != null

  # Point-in-time restore must reach back less far than soft delete.
  point_in_time_restore_days = var.recovery_window_days - 1

  containers_with_lifecycle = {
    for name, c in var.containers : name => c
    if c.delete_after_days != null || c.move_to_cool_after_days != null
  }
}

###############################################################################
# The storage account
###############################################################################

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = local.location

  # General purpose v2, standard performance, hot tier: the right fit for
  # uploads, media and generated documents.
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  access_tier              = "Hot"
  account_replication_type = var.replication_type

  # --- Transport and encryption ---------------------------------------------
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true

  # --- Identity-only access ---------------------------------------------------
  # No account keys, no account-key SAS, no anonymous containers, no local
  # (SFTP) users. Applications and people authenticate with Entra ID and are
  # authorised with the role assignments below. There is no secret to leak,
  # rotate or paste into an app setting.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  local_user_enabled              = false
  sftp_enabled                    = false

  # Data may only be copied in from accounts of our own tenant, and may not be
  # replicated to another tenant.
  allowed_copy_scope               = "AAD"
  cross_tenant_replication_enabled = false

  # --- Network ----------------------------------------------------------------
  # Closed unless the caller names the networks the application runs in.
  public_network_access_enabled = local.public_endpoint_needed

  network_rules {
    default_action             = var.allow_public_network_access ? "Allow" : "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  # --- Protection against mistakes -------------------------------------------
  blob_properties {
    # Overwrites keep the previous version of the file.
    versioning_enabled = true

    # Deleted files and deleted containers stay recoverable.
    delete_retention_policy {
      days = var.recovery_window_days
    }

    container_delete_retention_policy {
      days = var.recovery_window_days
    }

    # Whole containers can be rolled back to an earlier moment (e.g. after a
    # buggy release corrupted or deleted many files). Needs the change feed.
    change_feed_enabled           = true
    change_feed_retention_in_days = var.recovery_window_days

    restore_policy {
      days = local.point_in_time_restore_days
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [var.cors_allowed_origins] : []

      content {
        allowed_origins    = cors_rule.value
        allowed_methods    = ["GET", "HEAD", "PUT", "OPTIONS"]
        allowed_headers    = ["*"]
        exposed_headers    = ["ETag", "Content-Length", "x-ms-request-id", "x-ms-version-id"]
        max_age_in_seconds = 3600
      }
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.private_dns_zone_id == null || var.private_endpoint_subnet_id != null
      error_message = "private_dns_zone_id only makes sense together with private_endpoint_subnet_id: set the subnet in which the private endpoint should be created, or remove private_dns_zone_id."
    }
  }
}

# Not an error (the account is still created, safely closed) but worth telling
# the developer at plan time rather than letting them find out from a 403.
check "application_can_reach_storage" {
  assert {
    condition     = local.network_path_configured
    error_message = "No network can reach this storage account yet, so the application will get 403 errors. Set allowed_subnet_ids to the subnet(s) the application runs in (AKS node subnet / App Service integration subnet), or private_endpoint_subnet_id if your platform uses Private Link. Only if internet clients must reach the files directly, set allow_public_network_access = true."
  }
}

###############################################################################
# Containers - always private, managed through ARM (no data-plane access
# needed by the pipeline)
###############################################################################

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

###############################################################################
# Lifecycle: keep cost under control without anyone having to think about it
###############################################################################

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  # Versioning keeps every overwritten copy; clean old ones up.
  rule {
    name    = "expire-previous-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = var.previous_version_retention_days
      }
    }
  }

  # Per-container expiry / tiering requested by the application team.
  dynamic "rule" {
    for_each = local.containers_with_lifecycle

    content {
      name    = "container-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than = rule.value.move_to_cool_after_days
          delete_after_days_since_modification_greater_than       = rule.value.delete_after_days
        }
      }
    }
  }
}

###############################################################################
# Who may use the data
###############################################################################

# The application: read, write and delete blobs in this account (this role also
# lets it issue short-lived, identity-signed download/upload links).
resource "azurerm_role_assignment" "application" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Application identity: read/write access to its files. Managed by the app-storage module."
}

# People: read-only, via groups.
resource "azurerm_role_assignment" "reader" {
  for_each = toset(var.reader_group_object_ids)

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
  principal_type       = "Group"
  description          = "Read-only access for troubleshooting. Managed by the app-storage module."
}

###############################################################################
# Optional private endpoint for the blob service
###############################################################################

resource "azurerm_private_endpoint" "blob" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

  name                = "pe-${azurerm_storage_account.this.name}-blob"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = local.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id != null ? [var.private_dns_zone_id] : []

    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }

  tags = local.tags
}

###############################################################################
# Optional audit trail
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "audit-to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Who changed or removed what. Reads are left out on purpose: for media that
  # is served to users they are high-volume and expensive to ingest.
  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

###############################################################################
# Guard rail against accidental deletion
###############################################################################

resource "azurerm_management_lock" "this" {
  count = var.delete_lock_enabled ? 1 : 0

  name       = "do-not-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Holds application data. Managed by the app-storage module; set delete_lock_enabled = false there to remove."

  # Created last and removed first, so that a deliberate change (lock disabled)
  # or `tofu destroy` is not blocked by the lock the module itself placed.
  depends_on = [
    azurerm_storage_container.this,
    azurerm_storage_management_policy.this,
    azurerm_role_assignment.application,
    azurerm_role_assignment.reader,
    azurerm_private_endpoint.blob,
    azurerm_monitor_diagnostic_setting.blob,
  ]
}
