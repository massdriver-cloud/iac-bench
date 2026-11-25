# -----------------------------------------------------------------------------
# Standard storage account for application teams.
#
# One instance of this module = one storage account for one application in one
# environment, placed in that application's existing resource group.
# -----------------------------------------------------------------------------

locals {
  # Each application already owns a resource group per environment,
  # conventionally named "<application>-<environment>" (e.g. "orders-staging").
  # The storage account lives there; this module never creates resource groups.
  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")

  # Azure storage account names allow only lowercase letters and digits and
  # are at most 24 characters long, so we derive one deterministically from
  # the application and environment names. Teams that need a specific name
  # (e.g. because the derived one is already taken globally) can override it
  # via var.storage_account_name.
  storage_account_name = coalesce(
    var.storage_account_name,
    substr(replace("${var.application_name}${var.environment}", "/[^a-z0-9]/", ""), 0, 24),
  )

  tags = merge(
    {
      application = var.application_name
      environment = var.environment
      managed_by  = "opentofu"
      module      = "standard-app-storage"
    },
    var.extra_tags,
  )
}

check "storage_account_name_is_valid" {
  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", local.storage_account_name))
    error_message = "The derived storage account name \"${local.storage_account_name}\" is not valid (3-24 lowercase alphanumeric characters). Set storage_account_name explicitly."
  }
}

# The storage account itself.
#
# The security posture is deliberately fixed so that every account an app team
# gets comes out the same:
#
#   * TLS 1.2+ and HTTPS-only traffic.
#   * Shared keys disabled: no connection strings, no account keys, no
#     account-key SAS. Applications authenticate with their own Entra ID
#     identity, which is granted data access below, and the account defaults
#     to Entra ID (OAuth) authorization.
#   * Anonymous/public access to containers and blobs is blocked.
#   * Blob versioning and soft delete are on, so an accidental overwrite or
#     delete can be recovered for 7 days.
resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = true
  local_user_enabled               = false
  cross_tenant_replication_enabled = false

  blob_properties {
    versioning_enabled       = true
    last_access_time_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# Standard blob containers.
#
# Every application gets the same default layout for the kinds of files it
# works with:
#
#   uploads - files users upload
#   media   - images and videos
#   reports - generated reports and exports
#
# Containers are private (no anonymous access). Applications reach the data
# through the role assignments below, never through container ACLs.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

# Give each of the application's identities read/write access to the blob
# data - but not to the storage account itself. "Storage Blob Data
# Contributor" is the built-in role for reading and writing blobs; the
# control plane (account settings, containers) stays with the platform team.
#
# This is what makes disabling shared keys safe: AKS workload identities and
# App Service managed identities both authenticate to Azure Storage natively
# with Entra ID.
resource "azurerm_role_assignment" "blob_data_contributor" {
  for_each = toset(var.app_identity_principal_ids)

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

# Generated reports and exports are typically read right after they are
# produced and rarely afterwards, so they move down tiers over time:
# cool after 30 days, archive after 120 days. Nothing is ever deleted.
resource "azurerm_storage_management_policy" "reports" {
  count = var.enable_reports_lifecycle_policy ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "CoolAndArchiveReports"
    enabled = true

    filters {
      prefix_match = ["reports/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 120
      }
    }
  }
}
