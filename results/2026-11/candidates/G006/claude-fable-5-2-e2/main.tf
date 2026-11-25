###############################################################################
# Context: the application's existing resource group
###############################################################################

data "azurerm_client_config" "current" {}

# The resource group is owned by the application / platform and is looked up,
# never created or changed here.
data "azurerm_resource_group" "app" {
  name = coalesce(var.resource_group_name, "${var.application}-${var.environment}")
}

locals {
  is_production = var.environment == "prod"

  resource_group_name = data.azurerm_resource_group.app.name
  location            = coalesce(var.location, data.azurerm_resource_group.app.location)

  # Storage account names are global across all of Azure, 3-24 characters,
  # lowercase letters and digits only. Build "st<app><env><hash>": readable,
  # and the hash (subscription + resource group + app + env) makes it unique
  # yet stable between runs.
  env_short   = lookup({ staging = "stg", preprod = "pre" }, var.environment, var.environment)
  app_compact = substr(replace(var.application, "-", ""), 0, 12)
  name_hash = substr(sha256(lower(join("/", [
    data.azurerm_client_config.current.subscription_id,
    local.resource_group_name,
    var.application,
    var.environment,
  ]))), 0, 6)
  storage_account_name = coalesce(var.storage_account_name, "st${local.app_compact}${local.env_short}${local.name_hash}")

  # Environment-driven defaults.
  replication_type    = coalesce(var.replication_type, local.is_production ? "GRS" : "LRS")
  recovery_days       = coalesce(var.recovery_days, local.is_production ? 30 : 7)
  delete_lock_enabled = coalesce(var.delete_lock_enabled, local.is_production)

  # The firewall always denies by default. The public endpoint is only switched
  # on at all when there is something on the allow-list that needs it.
  public_endpoint_needed = length(var.allowed_subnet_ids) + length(var.allowed_ip_ranges) > 0
  private_endpoint       = var.private_endpoint_subnet_id != null
  has_network_path       = local.public_endpoint_needed || local.private_endpoint

  tags = merge(var.tags, {
    application = var.application
    environment = var.environment
    managed-by  = "opentofu"
    module      = "app-storage"
  })
}

###############################################################################
# The storage account
###############################################################################

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name
  location            = local.location

  # General-purpose v2, standard performance, hot by default: the right fit for
  # uploads, media and generated documents.
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  access_tier              = "Hot"
  account_replication_type = local.replication_type

  # --- Access: Entra ID identities only -------------------------------------
  # No account keys and no key-based SAS: nothing to leak, rotate or paste into
  # an app setting. Applications sign in with their own identity.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false
  sftp_enabled                    = false

  # Nothing in this account can ever be made anonymously readable.
  allow_nested_items_to_be_public = false

  # --- Transport and encryption ----------------------------------------------
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true

  # --- Keep data inside our tenant -------------------------------------------
  cross_tenant_replication_enabled = false
  allowed_copy_scope               = "AAD"

  # --- Network: deny unless explicitly allowed -------------------------------
  public_network_access_enabled = local.public_endpoint_needed

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  # --- Protection against accidental deletes and overwrites ------------------
  blob_properties {
    # Every overwrite keeps the previous version; every delete is recoverable.
    versioning_enabled = true

    delete_retention_policy {
      days = local.recovery_days
    }

    container_delete_retention_policy {
      days = local.recovery_days
    }

    # Point-in-time restore: roll containers back to how they were at a moment
    # in the past (needs the change feed; must be shorter than soft delete).
    change_feed_enabled           = true
    change_feed_retention_in_days = local.recovery_days

    restore_policy {
      days = local.recovery_days - 1
    }

    # Needed for the "move to cool when nobody reads it" lifecycle rule.
    last_access_time_enabled = var.cool_after_days_without_access != null

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []

      content {
        allowed_origins    = var.cors_allowed_origins
        allowed_methods    = ["GET", "HEAD", "PUT", "OPTIONS"]
        allowed_headers    = ["*"]
        exposed_headers    = ["ETag", "Content-Length", "x-ms-request-id"]
        max_age_in_seconds = 3600
      }
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(var.private_dns_zone_ids) == 0 || local.private_endpoint
      error_message = "private_dns_zone_ids only has an effect together with private_endpoint_subnet_id. Set the subnet for the private endpoint, or remove private_dns_zone_ids."
    }
  }
}

###############################################################################
# Containers
###############################################################################

# Created through Azure Resource Manager (storage_account_id), so this works
# even though the machine running `tofu` is outside the storage firewall.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

###############################################################################
# Housekeeping (lifecycle management)
###############################################################################

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  # Account-wide: without this, versioning would keep every old copy forever.
  rule {
    name    = "default-housekeeping"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      dynamic "base_blob" {
        for_each = var.cool_after_days_without_access != null ? [1] : []

        content {
          tier_to_cool_after_days_since_last_access_time_greater_than = var.cool_after_days_without_access
          auto_tier_to_hot_from_cool_enabled                          = true
        }
      }

      # Old versions are only there for recovery; drop them once the recovery
      # window has passed.
      version {
        delete_after_days_since_creation = local.recovery_days
      }
    }
  }

  # Per container: expire short-lived files (reports, exports, ...).
  dynamic "rule" {
    for_each = { for name, c in var.containers : name => c if c.delete_after_days != null }

    content {
      name    = "expire-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          delete_after_days_since_creation_greater_than = rule.value.delete_after_days
        }
      }
    }
  }

  depends_on = [azurerm_storage_container.this]
}
