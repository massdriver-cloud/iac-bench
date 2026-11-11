# Illustrative production instantiation. The resource IDs below are
# placeholders: replace them with real ones before applying.
name        = "orders-api"
environment = "prod"
location    = "westeurope"

image = {
  registry   = "contosoplatform.azurecr.io"
  repository = "payments/orders-api"
  tag        = "1.8.3"
}
container_registry_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/contosoplatform"

app_settings = {
  LOG_LEVEL = "info"
}
key_vault_secrets = {
  DB_PASSWORD = "https://kv-orders-prod.vault.azure.net/secrets/db-password"
}
key_vault_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-orders-prod-data/providers/Microsoft.KeyVault/vaults/kv-orders-prod",
]

capacity = {
  sku           = "P2v3"
  min_instances = 3
  max_instances = 12
}

ingress = {
  mode           = "restricted"
  front_door_ids = ["11111111-2222-3333-4444-555555555555"]
  allowed_cidrs  = ["203.0.113.0/24"]

  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-private-endpoints"
  private_dns_zone_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net",
  ]
}

vnet_integration_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-appservice"

alerts = {
  action_group_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.Insights/actionGroups/ag-sre-oncall",
  ]
}
