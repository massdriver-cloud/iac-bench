locals {
  application_name_part = replace(lower(var.application_name), "/[^a-z0-9]/", "")
  environment_name_part = replace(lower(var.environment), "/[^a-z0-9]/", "")

  # A 16-character prefix plus the eight-character suffix always fits the
  # 24-character storage account limit.
  generated_name_prefix = substr(
    "st${local.application_name_part}${local.environment_name_part}",
    0,
    16
  )

  storage_account_name = (
    var.storage_account_name != null
    ? var.storage_account_name
    : "${local.generated_name_prefix}${random_string.suffix[0].result}"
  )

  configure_network_rules = (
    var.public_network_access_enabled &&
    (length(var.allowed_ip_ranges) > 0 || length(var.allowed_subnet_ids) > 0)
  )

  tags = merge(
    {
      application = var.application_name
      environment = var.environment
      managed-by  = "OpenTofu"
    },
    var.tags
  )
}

resource "random_string" "suffix" {
  count = var.storage_account_name == null ? 1 : 0

  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    application   = var.application_name
    environment   = var.environment
    resourceGroup = var.resource_group_name
  }
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = var.public_network_access_enabled
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  # This is a general-purpose blob account, not a data lake, SFTP server, or
  # NFS share. Keeping those surfaces off makes the default easier to secure.
  is_hns_enabled     = false
  sftp_enabled       = false
  nfsv3_enabled      = false
  local_user_enabled = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  dynamic "network_rules" {
    for_each = local.configure_network_rules ? [true] : []

    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = tolist(var.allowed_ip_ranges)
      virtual_network_subnet_ids = tolist(var.allowed_subnet_ids)
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition = (
        var.public_network_access_enabled ||
        (length(var.allowed_ip_ranges) == 0 && length(var.allowed_subnet_ids) == 0)
      )
      error_message = "allowed_ip_ranges and allowed_subnet_ids cannot be used when public_network_access_enabled is false. Configure private endpoints separately instead."
    }
  }
}

# Containers are created through Azure Resource Manager rather than the blob
# data plane. That lets shared-key access stay disabled from the first apply
# and avoids requiring the deployment identity to have blob data-plane access.
resource "azapi_resource" "containers" {
  for_each = var.container_names

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.value
  parent_id = "${azurerm_storage_account.this.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_role_assignment" "application_blob_data" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_identity_object_id
  principal_type       = "ServicePrincipal"
}

# Versioning protects application data from overwrites. This policy prevents
# old versions and snapshots from accumulating forever; it never expires the
# current version of an application blob.
resource "azurerm_storage_management_policy" "data_protection" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-noncurrent-blob-data"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = var.noncurrent_version_retention_days
      }

      snapshot {
        delete_after_days_since_creation_greater_than = var.noncurrent_version_retention_days
      }
    }
  }
}
