data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

locals {
  # The group ID includes the subscription. Hashing it gives each app/environment
  # a stable account name without requiring callers to invent a globally unique name.
  account_name = "st${substr(sha256(lower(data.azurerm_resource_group.app.id)), 0, 22)}"
  tags         = merge(data.azurerm_resource_group.app.tags, var.tags)
  subnet_parts = var.private_network == null ? [] : split("/", var.private_network.subnet_id)
}

resource "azurerm_storage_account" "app" {
  name                     = local.account_name
  resource_group_name      = data.azurerm_resource_group.app.name
  location                 = data.azurerm_resource_group.app.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  local_user_enabled               = false
  cross_tenant_replication_enabled = false
  public_network_access_enabled    = var.private_network == null

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "app" {
  for_each = var.container_names

  name                  = each.key
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "app_blob" {
  for_each = azurerm_storage_container.app

  scope                            = each.value.resource_manager_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.application_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

data "azurerm_virtual_network" "endpoint" {
  count = var.private_network == null ? 0 : 1

  name                = local.subnet_parts[8]
  resource_group_name = local.subnet_parts[4]

  lifecycle {
    postcondition {
      condition     = lower(self.id) == lower(join("/", slice(local.subnet_parts, 0, 9)))
      error_message = "The private endpoint subnet must be in a VNet in the provider's subscription."
    }
  }
}

resource "azurerm_private_endpoint" "blob" {
  count = var.private_network == null ? 0 : 1

  name                = "${local.account_name}-blob"
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_virtual_network.endpoint[0].location
  subnet_id           = var.private_network.subnet_id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.app.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.private_network.private_dns_zone_id]
  }

  tags = local.tags
}
