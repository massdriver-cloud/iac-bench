# A production service using most of the module's options.
# All IDs below are placeholders - replace them with real ones.
name        = "orders-api"
environment = "prod"
location    = "westeurope"

tags = {
  team        = "payments"
  cost-center = "cc-1234"
}

# What runs
image                 = "contoso.azurecr.io/payments/orders-api:1.4.2"
container_registry_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/contoso"
container_port        = 8080

app_settings = {
  LOG_LEVEL     = "info"
  FEATURE_FLAGS = "checkout-v2"
}

key_vault_secrets = {
  DB_PASSWORD = "https://kv-payments-prod.vault.azure.net/secrets/orders-db-password"
}
key_vault_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.KeyVault/vaults/kv-payments-prod",
]

# Capacity and availability
sku_name      = "P2v3"
min_instances = 3
max_instances = 9

# Health
health_check_path = "/healthz"

# Rollout in progress: 1.5.0 is being verified on staging
staging_image = "contoso.azurecr.io/payments/orders-api:1.5.0"
staging_app_settings = {
  FEATURE_FLAGS = "checkout-v2,checkout-v3"
}

# Traffic: only through our Front Door profile and from the office range,
# plus a private endpoint for in-VNet callers
front_door_id              = "11111111-2222-3333-4444-555555555555"
allowed_ip_ranges          = ["203.0.113.0/24"]
integration_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-appsvc-integration"
private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-private-endpoints"
private_dns_zone_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net",
]
cors_allowed_origins = ["https://shop.contoso.com"]

# Observability: central workspace, page the on-call action group
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-observability/providers/Microsoft.OperationalInsights/workspaces/log-sre-central"
alert_action_group_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-observability/providers/Microsoft.Insights/actionGroups/ag-sre-oncall",
]
alert_email_addresses = ["payments-team@contoso.com"]
alert_thresholds = {
  response_time_seconds = 1
}
