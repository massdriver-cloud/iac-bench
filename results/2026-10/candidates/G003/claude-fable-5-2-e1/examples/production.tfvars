# Illustrative full-featured instantiation (IDs are placeholders - replace before applying).
name              = "orders-api-prod"
location          = "eastus2"
image             = "contosoacr.azurecr.io/payments/orders-api:1.4.2"
health_check_path = "/healthz"

registry = {
  acr_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/contosoacr"
}

app_settings = {
  LOG_LEVEL = "info"
}

key_vault = {
  id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.KeyVault/vaults/kv-orders-prod"
  secrets = { DB_PASSWORD = "orders-db-password" }
}

capacity = {
  sku           = "P2v3"
  min_instances = 3
  max_instances = 12
}

network = {
  allowed_service_tags  = ["AzureFrontDoor.Backend"]
  allowed_cidrs         = ["203.0.113.0/24"]
  integration_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-appsvc"
  private_endpoint = {
    subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-private-endpoints"
    private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"]
  }
}

alerts = {
  action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.Insights/actionGroups/ag-sre-oncall"]
}

tags = {
  team        = "payments"
  environment = "prod"
}
