data "azurerm_client_config" "current" {}

locals {
  # Storage account names: 3-24 chars, lowercase letters and digits only,
  # globally unique across all of Azure. The generated name is
  #   st + <app name, hyphens removed> + <environment> + <6-char hash>
  # The deterministic hash (subscription / resource group / app / environment)
  # keeps the name stable for a given app in a given environment while making
  # global collisions vanishingly unlikely. Worst-case length is
  # 2 + 9 + 7 + 6 = 24, enforced by the variable validations.
  name_hash = substr(md5(join("/", [
    data.azurerm_client_config.current.subscription_id,
    var.resource_group_name,
    var.app_name,
    var.environment,
  ])), 0, 6)

  storage_account_name = coalesce(
    var.name_override,
    "st${replace(var.app_name, "-", "")}${var.environment}${local.name_hash}"
  )

  # Redundancy: ZRS in prod, LRS everywhere else, unless the caller overrides.
  account_replication_type = coalesce(
    var.account_replication_type,
    var.environment == "prod" ? "ZRS" : "LRS"
  )

  # Only lock the firewall down when the caller gives us something to allow;
  # denying everything with no exceptions would cut the application off.
  network_locked_down = length(var.network_allowed_subnet_ids) > 0 || length(var.network_allowed_ip_rules) > 0

  tags = merge({
    application = var.app_name
    environment = var.environment
    managed-by  = "opentofu"
  }, var.tags)
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.account_replication_type
  access_tier              = "Hot"

  # Transport security.
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Identity-first authorization: no anonymous access, Entra (OAuth) is the
  # portal default, and shared keys / connection strings / account SAS are off
  # unless a team explicitly opts back in for a legacy client.
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  shared_access_key_enabled       = var.shared_access_key_enabled
  local_user_enabled              = false

  # Not a data lake, no SFTP, no cross-tenant replication. Double encryption
  # at rest (infrastructure encryption) costs nothing and is set at creation.
  is_hns_enabled                    = false
  sftp_enabled                      = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = true

  # Recoverability: versioning, change feed and soft delete on blobs and
  # containers, so an accidental delete or overwrite is not an incident.
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  network_rules {
    default_action             = local.network_locked_down ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.network_allowed_ip_rules
    virtual_network_subnet_ids = var.network_allowed_subnet_ids
  }

  tags = local.tags
}

# Containers are provisioned through the Azure control plane (ARM) rather than
# the storage data plane. That keeps provisioning working even though shared
# keys are disabled: the identity running OpenTofu needs no data-plane role
# on the account it just created.
resource "azapi_resource" "container" {
  for_each = var.containers

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01"
  parent_id = "${azurerm_storage_account.this.id}/blobServices/default"
  name      = each.value

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

# The application authenticates with its own Entra identity — workload
# identity on AKS, managed identity on App Service. No keys, no connection
# strings, no SAS tokens to rotate or leak.
resource "azurerm_role_assignment" "app_blob_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_principal_id
}
