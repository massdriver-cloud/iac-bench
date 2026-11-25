# ---------------------------------------------------------------------------
# The storage account: one hardened, opinionated account per application
# environment. StorageV2, hot tier, locally-redundant, identity-only access.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = local.resource_group_name
  location            = local.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  # Security posture: encrypted in transit and at rest, modern TLS only,
  # no anonymous/public access, Entra ID (not keys) as the way in.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = var.public_network_access_enabled
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false

  # Data protection: recover from accidental deletes/overwrites by default.
  blob_properties {
    versioning_enabled = var.blob_versioning_enabled

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  # Deny-by-default firewall. Access happens through private endpoints
  # (see network.tf) or explicitly allowed subnets. Platform diagnostics
  # stay possible.
  network_rules {
    default_action             = "Deny"
    bypass                     = ["Logging", "Metrics"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# The data surfaces the application asked for. Containers are private;
# identities (not keys/SAS) are how the application gets to them.
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  for_each = var.blob_containers

  name               = each.value
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_storage_queue" "this" {
  for_each = var.queues

  name               = each.value
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = each.value
  storage_account_id = azurerm_storage_account.this.id

  # A ceiling, not a reservation: billing is based on stored data. 5120 GB
  # (5 TiB) is Azure's own default for a standard-tier share.
  quota = 5120
}
