# -----------------------------------------------------------------------------
# Zero-Secret RBAC: ACR Image Pull & Key Vault Secret Resolution
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull_production" {
  count = local.grant_acr_pull_to_system_identity ? 1 : 0

  scope                = var.application.container.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = local.grant_acr_pull_to_system_identity && var.rollout.staging_slot_enabled ? 1 : 0

  scope                = var.application.container.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_production" {
  count = local.grant_kv_secrets_to_system_identity ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_staging" {
  count = local.grant_kv_secrets_to_system_identity && var.rollout.staging_slot_enabled ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

# -----------------------------------------------------------------------------
# Private Ingress Endpoint (Optional)
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "this" {
  count = var.network.private_endpoint != null ? 1 : 0

  name                = local.private_endpoint_name
  location            = local.location
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  subnet_id           = var.network.private_endpoint.subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.web_app_name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.network.private_endpoint.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "privatelink-azurewebsites-net"
      private_dns_zone_ids = var.network.private_endpoint.private_dns_zone_ids
    }
  }
}
